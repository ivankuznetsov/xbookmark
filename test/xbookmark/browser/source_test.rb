# frozen_string_literal: true

require "test_helper"
require "xbookmark/browser/source"

# Self-contained Ferrum-shaped fakes (no cross-file deps so this runs alone).
class StubXchg
  def initialize(url, body, id)
    @url = url
    @body = body
    @id = id
  end

  attr_reader :id

  def request = Struct.new(:url).new(@url)
  def response = Struct.new(:body).new(@body)
end

class StubNetwork
  def initialize(page, wait_raises: false)
    @page = page
    @wait_raises = wait_raises
  end

  def wait_for_idle
    raise "network idle timeout" if @wait_raises

    nil
  end

  def traffic = @page.exchanges
end

# Reveals one more captured GraphQL exchange per scroll, simulating an
# infinite-scroll timeline lazily loading pages.
class StubTimelinePage
  attr_reader :scrolls, :visited

  def initialize(bodies, url_kind: :bookmarks, current_url: nil, wait_raises: false)
    @url_kind = url_kind
    @revealed = 1
    @scrolls = 0
    @visited = []
    @current_url = current_url || Xbookmark::Browser::Source::BOOKMARKS_URL
    @network = StubNetwork.new(self, wait_raises: wait_raises)
    op = url_kind == :tweet ? "TweetResultByRestId" : "Bookmarks"
    @exchanges = bodies.each_with_index.map do |body, i|
      StubXchg.new("https://x.com/i/api/graphql/abc/#{op}?p=#{i}", body, i)
    end
  end

  def go_to(url) = @visited << url
  def current_url = @current_url
  attr_reader :network

  def execute(_js)
    @scrolls += 1
    @revealed += 1 if @revealed < @exchanges.size
    nil
  end

  def exchanges = @exchanges.first(@revealed)
end

# Returns a controlled, cumulative batch of exchanges per drain so a walk can be
# driven through a mid-stream empty round and back into data.
class GappyTimelinePage
  def initialize(traffic_batches)
    @batches = traffic_batches
    @drains = 0
    @current_url = Xbookmark::Browser::Source::BOOKMARKS_URL
  end

  def go_to(_) = nil
  def current_url = @current_url
  def execute(_) = nil
  def network = self
  def wait_for_idle = nil

  def traffic
    batch = @batches[@drains] || @batches.last || []
    @drains += 1
    batch
  end
end

class StubSession
  attr_reader :quits

  def initialize(page)
    @page = page
    @quits = 0
  end

  def with_page
    yield @page
  end

  def quit = @quits += 1
end

describe Xbookmark::Browser::Source do
  let(:config) { Struct.new(:vault_path).new("/tmp/wiki") }

  def bookmarks_body(ids:, cursor:)
    entries = ids.map do |id|
      { "content" => { "entryType" => "TimelineTimelineItem", "itemContent" => {
        "itemType" => "TimelineTweet", "tweet_results" => { "result" => {
          "__typename" => "Tweet", "rest_id" => id,
          "core" => { "user_results" => { "result" => {
            "rest_id" => "u1", "legacy" => { "screen_name" => "alice", "name" => "Alice" }
          } } },
          "legacy" => { "id_str" => id, "user_id_str" => "u1", "full_text" => "t#{id}",
                        "created_at" => "Thu Jan 01 00:00:00 +0000 2026", "conversation_id_str" => id }
        } } }
      } }
    end
    entries << { "content" => { "entryType" => "TimelineTimelineCursor", "cursorType" => "Bottom", "value" => cursor } }
    JSON.generate({ "data" => { "bookmark_timeline_v2" => { "timeline" => {
      "instructions" => [{ "type" => "TimelineAddEntries", "entries" => entries }]
    } } } })
  end

  it "walks the timeline by scrolling and stops when the cursor stops advancing" do
    bodies = [
      bookmarks_body(ids: %w[1], cursor: "c1"),
      bookmarks_body(ids: %w[2], cursor: "c2"),
      bookmarks_body(ids: %w[3], cursor: "c2") # cursor unchanged → end of history
    ]
    page = StubTimelinePage.new(bodies)
    session = StubSession.new(page)
    source = described_class.new(config: config, session: session)

    yielded = []
    source.bookmarks(user_id: nil) { |env| yielded << env }

    assert_equal [%w[1], %w[2], %w[3]], yielded.map { |e| e["data"].map { |t| t["id"] } }
    assert_equal "c1", yielded.first["meta"]["next_token"]
    assert_equal 2, page.scrolls
    assert_equal 1, session.quits
    assert_equal [Xbookmark::Browser::Source::BOOKMARKS_URL], page.visited
  end

  it "stops the walk when a page exposes no further cursor" do
    no_cursor = JSON.generate({ "data" => { "bookmark_timeline_v2" => { "timeline" => {
      "instructions" => [{ "type" => "TimelineAddEntries", "entries" => [
        { "content" => { "entryType" => "TimelineTimelineItem", "itemContent" => {
          "itemType" => "TimelineTweet", "tweet_results" => { "result" => {
            "__typename" => "Tweet", "rest_id" => "9",
            "legacy" => { "id_str" => "9", "full_text" => "t", "created_at" => "Thu Jan 01 00:00:00 +0000 2026" }
          } } }
        } }
      ] }]
    } } } })
    page = StubTimelinePage.new([no_cursor])
    session = StubSession.new(page)
    source = described_class.new(config: config, session: session)

    yielded = []
    source.bookmarks { |env| yielded << env }

    assert_equal 1, yielded.size
    assert_equal 0, page.scrolls
  end

  it "raises SessionExpired when no Bookmarks response is ever captured (checkpointed session)" do
    empty = JSON.generate({ "data" => {} })
    # No Bookmarks-matching traffic at all: an authenticated page always issues
    # at least one Bookmarks query, so zero captures means a wall served at the
    # same URL — surface it for AC3 re-login instead of a clean empty sync. The
    # walk still bounds its scrolling rather than looping forever.
    page = StubTimelinePage.new([empty], url_kind: :tweet)
    session = StubSession.new(page)
    source = described_class.new(config: config, session: session)

    assert_raises(Xbookmark::Browser::SessionExpired) { source.bookmarks { |_| flunk "no page expected" } }
    assert_equal Xbookmark::Browser::Source::MAX_EMPTY_ROUNDS, page.scrolls
    assert_equal 1, session.quits
  end

  it "resets empty-round counting when data resumes after a transient empty settle" do
    # drain 1 → page A; drain 2 → nothing new (mid-stream empty); drain 3 → page
    # B whose cursor repeats A's, ending the walk. The middle empty round must
    # not prematurely truncate the timeline.
    a = StubXchg.new("https://x.com/i/api/graphql/abc/Bookmarks?p=0", bookmarks_body(ids: %w[1], cursor: "a"), 0)
    b = StubXchg.new("https://x.com/i/api/graphql/abc/Bookmarks?p=1", bookmarks_body(ids: %w[2], cursor: "a"), 1)
    page = GappyTimelinePage.new([[a], [a], [a, b]])
    source = described_class.new(config: config, session: StubSession.new(page))

    yielded = []
    source.bookmarks { |env| yielded << env }

    assert_equal [%w[1], %w[2]], yielded.map { |e| e["data"].map { |t| t["id"] } }
  end

  it "yields an empty page instead of aborting when normalizing one page raises" do
    page = StubTimelinePage.new([bookmarks_body(ids: %w[1], cursor: "c1")])
    source = described_class.new(config: config, session: StubSession.new(page))
    Xbookmark::Browser::Normalizer.any_instance.stubs(:envelope).raises("boom")

    yielded = []
    capture_stderr { source.bookmarks { |env| yielded << env } }

    assert_equal 1, yielded.size
    assert_empty yielded.first["data"]
  end

  it "honors a break in the consumer block and still quits the session" do
    bodies = [
      bookmarks_body(ids: %w[1], cursor: "c1"),
      bookmarks_body(ids: %w[2], cursor: "c2")
    ]
    page = StubTimelinePage.new(bodies)
    session = StubSession.new(page)
    source = described_class.new(config: config, session: session)

    yielded = []
    source.bookmarks do |env|
      yielded << env
      break
    end

    assert_equal 1, yielded.size
    assert_equal 1, session.quits
  end

  it "maps an unexpected browser error during bookmarks to TransientError" do
    page = StubTimelinePage.new([bookmarks_body(ids: %w[1], cursor: "c1")])
    page.stubs(:go_to).raises("cdp boom")
    session = StubSession.new(page)
    source = described_class.new(config: config, session: session)

    assert_raises(Xbookmark::TransientError) { source.bookmarks { |_| flunk "no page expected" } }
    assert_equal 1, session.quits
  end

  it "raises TransientError when an unsettled walk captures nothing (stalled, not expired)" do
    page = StubTimelinePage.new([JSON.generate({ "data" => {} })], url_kind: :tweet, wait_raises: true)
    source = described_class.new(config: config, session: StubSession.new(page))

    assert_raises(Xbookmark::TransientError) { source.bookmarks { |_| flunk "no page expected" } }
  end

  it "raises SessionExpired when the bookmarks page redirects to login" do
    page = StubTimelinePage.new([bookmarks_body(ids: %w[1], cursor: "c1")],
                                current_url: "https://x.com/i/flow/login")
    session = StubSession.new(page)
    source = described_class.new(config: config, session: session)

    assert_raises(Xbookmark::Browser::SessionExpired) { source.bookmarks { |_| flunk "should not yield" } }
    assert_equal 1, session.quits
  end

  it "tolerates wait_for_idle timeouts while settling" do
    page = StubTimelinePage.new([bookmarks_body(ids: %w[1], cursor: "c1")], wait_raises: true)
    session = StubSession.new(page)
    source = described_class.new(config: config, session: session)

    yielded = []
    err = capture_stderr { source.bookmarks { |env| yielded << env } }
    assert_equal 1, yielded.size
    assert_match(/history tail may be incomplete/, err, "an unsettled empty-rounds stop warns about possible truncation")
  end

  it "returns an Enumerator without building or quitting a session when called without a block" do
    session = StubSession.new(StubTimelinePage.new([]))
    source = described_class.new(config: config, session: session)
    assert_kind_of Enumerator, source.bookmarks
    assert_equal 0, session.quits, "the no-block path must not lazily build a session just to quit it"
  end

  it "accepts and ignores pagination_token for X::Client contract parity" do
    page = StubTimelinePage.new([bookmarks_body(ids: %w[1], cursor: "c1")])
    source = described_class.new(config: config, session: StubSession.new(page))

    yielded = []
    source.bookmarks(user_id: "42", pagination_token: "ignored", max_results: 50) { |env| yielded << env }
    assert_equal 1, yielded.size
  end

  it "exposes the same bookmarks keyword contract as X::Client" do
    keywords = lambda do |klass|
      klass.instance_method(:bookmarks).parameters.select { |type, _| %i[key keyreq].include?(type) }.map(&:last).sort
    end
    assert_equal keywords.call(Xbookmark::X::Client), keywords.call(described_class)
    assert_respond_to described_class.new(config: config), :get_tweet
  end

  it "closes nothing when the source was never used" do
    assert_nil described_class.new(config: config).close
  end

  it "builds a headless Session from config when none is injected" do
    fake_session = StubSession.new(StubTimelinePage.new([bookmarks_body(ids: %w[1], cursor: "c1")]))
    Xbookmark::Browser::Session.expects(:new).with(config: config, headless: true).returns(fake_session)
    source = described_class.new(config: config)

    yielded = []
    source.bookmarks { |env| yielded << env }
    assert_equal 1, yielded.size
  end

  # ---- get_tweet ----

  def tweet_detail_body(id)
    JSON.generate({ "data" => { "tweetResult" => { "result" => {
      "__typename" => "Tweet", "rest_id" => id,
      "core" => { "user_results" => { "result" => {
        "rest_id" => "u1", "legacy" => { "screen_name" => "alice", "name" => "Alice" }
      } } },
      "legacy" => { "id_str" => id, "user_id_str" => "u1", "full_text" => "single",
                    "created_at" => "Thu Jan 01 00:00:00 +0000 2026", "conversation_id_str" => id }
    } } } })
  end

  it "returns a single-tweet API v2 payload for get_tweet and reuses the session" do
    page = StubTimelinePage.new([tweet_detail_body("555")], url_kind: :tweet)
    session = StubSession.new(page)
    source = described_class.new(config: config, session: session)

    payload = source.get_tweet("555")

    assert_equal "555", payload["data"]["id"]
    assert_equal "alice", payload["includes"]["users"].first["username"]
    assert_equal ["https://x.com/i/web/status/555"], page.visited
    assert_equal 0, session.quits, "get_tweet keeps the browser alive; the Runner closes it"
    source.close
    assert_equal 1, session.quits
  end

  it "raises SourceUnavailable from get_tweet when no tweet is present in the capture" do
    page = StubTimelinePage.new([JSON.generate({ "data" => {} })], url_kind: :tweet)
    source = described_class.new(config: config, session: StubSession.new(page))

    assert_raises(Xbookmark::SourceUnavailable) { source.get_tweet("404") }
  end

  it "raises SourceUnavailable from get_tweet when the normalized result has no tweet" do
    empty_result = JSON.generate({ "data" => { "tweetResult" => { "result" => { "__typename" => "Tweet", "legacy" => {} } } } })
    page = StubTimelinePage.new([empty_result], url_kind: :tweet)
    source = described_class.new(config: config, session: StubSession.new(page))

    assert_raises(Xbookmark::SourceUnavailable) { source.get_tweet("404") }
  end

  it "raises SourceUnavailable from get_tweet when no tweet response is captured at all" do
    # The page issued only Bookmarks traffic, no single-tweet response.
    page = StubTimelinePage.new([bookmarks_body(ids: %w[1], cursor: "c1")], url_kind: :bookmarks)
    source = described_class.new(config: config, session: StubSession.new(page))

    assert_raises(Xbookmark::SourceUnavailable) { source.get_tweet("404") }
  end

  it "raises TransientError from get_tweet when the capture itself fails" do
    page = StubTimelinePage.new(["{bad json"], url_kind: :tweet)
    source = described_class.new(config: config, session: StubSession.new(page))

    assert_raises(Xbookmark::TransientError) { source.get_tweet("9") }
  end

  it "maps an unexpected browser error during get_tweet to TransientError" do
    page = StubTimelinePage.new([tweet_detail_body("1")], url_kind: :tweet)
    page.stubs(:go_to).raises("cdp boom")
    source = described_class.new(config: config, session: StubSession.new(page))

    assert_raises(Xbookmark::TransientError) { source.get_tweet("1") }
  end

  it "raises SessionExpired from get_tweet when redirected to login" do
    page = StubTimelinePage.new([tweet_detail_body("1")], url_kind: :tweet, current_url: "https://x.com/login")
    session = StubSession.new(page)
    source = described_class.new(config: config, session: session)

    assert_raises(Xbookmark::Browser::SessionExpired) { source.get_tweet("1") }
    assert_equal 0, session.quits, "the Runner owns closing the reused session"
  end
end
