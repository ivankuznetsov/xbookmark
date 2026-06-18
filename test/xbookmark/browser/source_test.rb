# frozen_string_literal: true

require "test_helper"
require "xbookmark/browser/source"
# Source no longer pulls in X::Client (it inlines its one constant), but the
# contract-parity test below still compares against it, so load it explicitly.
require "xbookmark/x/client"

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

# Serves one real Bookmarks page, then the session expires mid-walk: X stops
# issuing Bookmarks traffic and redirects to login at the same URL. Drains go
# empty (cleanly settled) so the empty-rounds break fires with pages>0.
class MidWalkExpiringPage
  attr_reader :scrolls

  def initialize(body)
    @exchange = StubXchg.new("https://x.com/i/api/graphql/abc/Bookmarks?p=0", body, 0)
    @drains = 0
    @scrolls = 0
    @current_url = Xbookmark::Browser::Source::BOOKMARKS_URL
  end

  def go_to(_) = nil
  def current_url = @current_url
  def network = self
  def wait_for_idle = nil

  def execute(_)
    @scrolls += 1
    nil
  end

  def traffic
    @drains += 1
    return [@exchange] if @drains == 1

    # After the first page the session is gone — the page now redirects to login
    # and X serves no further Bookmarks traffic.
    @current_url = "https://x.com/i/flow/login"
    []
  end
end

# A single-tweet load whose session expires *after* the initial guard: the URL
# is a clean tweet URL when go_to's guard runs, no tweet traffic is captured, and
# X has redirected to login by the time the page settles. Exercises get_tweet's
# re-guard that runs after settle, before the permanent SourceUnavailable.
class TweetExpiringAfterSettlePage
  def initialize
    @current_url = "https://x.com/i/web/status/1"
  end

  def go_to(_) = nil
  def current_url = @current_url
  def execute(_) = nil
  def network = self
  def wait_for_idle = nil

  def traffic
    # Draining (after the clean settle) reveals the post-redirect state, so the
    # initial guard saw a clean URL and only the re-guard catches the expiry.
    @current_url = "https://x.com/i/flow/login"
    []
  end
end

# Drains several single-tweet responses in one go (no scrolling), so get_tweet's
# stray-rejection (matching_tweet_envelope) can be exercised with the focal tweet
# and a stray quoted/hovercard tweet in either drain order. wait_raises stalls the
# settle to drive the transient-vs-permanent no-match classification.
class MultiTweetPage
  def initialize(bodies, current_url: nil, wait_raises: false)
    @current_url = current_url || "https://x.com/i/web/status/1"
    @wait_raises = wait_raises
    @exchanges = bodies.each_with_index.map do |body, i|
      StubXchg.new("https://x.com/i/api/graphql/abc/TweetResultByRestId?p=#{i}", body, i)
    end
  end

  def go_to(_) = nil
  def current_url = @current_url
  def execute(_) = nil
  def network = self

  def wait_for_idle
    raise "network idle timeout" if @wait_raises

    nil
  end

  def traffic = @exchanges
end

# A timeline whose Bottom cursor strictly advances on every scroll and never
# repeats, so the walk can only terminate by hitting MAX_TIMELINE_ITERATIONS.
# Traffic is cumulative (append-only), mirroring the real CDP buffer.
class StrictlyAdvancingPage
  attr_reader :scrolls

  def initialize
    @scrolls = 0
    @current_url = Xbookmark::Browser::Source::BOOKMARKS_URL
    @exchanges = [make(0)]
  end

  def go_to(_) = nil
  def current_url = @current_url
  def network = self
  def wait_for_idle = nil
  def traffic = @exchanges

  def execute(_)
    @scrolls += 1
    @exchanges << make(@exchanges.size)
    nil
  end

  private

  def make(i)
    body = JSON.generate({ "data" => { "bookmark_timeline_v2" => { "timeline" => { "instructions" => [
      { "type" => "TimelineAddEntries", "entries" => [
        { "content" => { "entryType" => "TimelineTimelineItem", "itemContent" => {
          "itemType" => "TimelineTweet", "tweet_results" => { "result" => {
            "__typename" => "Tweet", "rest_id" => "t#{i}",
            "legacy" => { "id_str" => "t#{i}", "full_text" => "t", "created_at" => "Thu Jan 01 00:00:00 +0000 2026" }
          } } } } },
        { "content" => { "entryType" => "TimelineTimelineCursor", "cursorType" => "Bottom", "value" => "c#{i}" } }
      ] }
    ] } } } })
    StubXchg.new("https://x.com/i/api/graphql/abc/Bookmarks?p=#{i}", body, i)
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
  include SourceContractTest

  let(:config) { Struct.new(:vault_path).new("/tmp/wiki") }

  # ---- shared source-contract hooks (see test/support/source_contract.rb) ----
  def contract_present_id = "555"
  def contract_missing_id = "404"

  def build_contract_bookmarks_source
    described_class.new(config: config,
                        session: StubSession.new(StubTimelinePage.new([bookmarks_body(ids: %w[1], cursor: "c1")])))
  end

  def build_contract_present_source
    described_class.new(config: config,
                        session: StubSession.new(StubTimelinePage.new([tweet_detail_body("555")], url_kind: :tweet)))
  end

  def build_contract_missing_source
    described_class.new(config: config,
                        session: StubSession.new(StubTimelinePage.new([JSON.generate({ "data" => {} })], url_kind: :tweet)))
  end

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

  # Temporarily shrinks the hard iteration cap so the backstop can be exercised
  # without a 10_000-iteration walk. remove_const first avoids a redefinition
  # warning.
  def with_max_timeline_iterations(count)
    klass = Xbookmark::Browser::Source
    original = klass::MAX_TIMELINE_ITERATIONS
    klass.send(:remove_const, :MAX_TIMELINE_ITERATIONS)
    klass.const_set(:MAX_TIMELINE_ITERATIONS, count)
    yield
  ensure
    klass.send(:remove_const, :MAX_TIMELINE_ITERATIONS)
    klass.const_set(:MAX_TIMELINE_ITERATIONS, original)
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

  it "raises a transient error when a data-bearing page exposes no Bottom cursor" do
    # X always emits a Bottom cursor (it merely repeats at end-of-history), so a
    # page that carried tweets but exposed none is an untrustworthy stop. The
    # transient error is surfaced *before* the page is yielded so a consumer that
    # breaks on the cursorless envelope cannot bypass it and seal a truncated
    # backfill (see the breaking-consumer test below).
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
    assert_raises(Xbookmark::TransientError) { source.bookmarks { |env| yielded << env } }
    assert_empty yielded, "the cursorless page raises before it is yielded, so a breaking consumer cannot seal a truncated backfill"
    assert_equal 0, page.scrolls, "a missing cursor stops the walk without further scrolling"
    assert_equal 1, session.quits
  end

  it "raises the transient stop before a consumer that breaks on a cursorless page can bypass it" do
    # The Runner drives pagination with `break unless next_token`. A cursorless
    # page yields meta with no next_token, so that consumer would break —
    # unwinding past the post-loop finish_walk guard and silently sealing a
    # truncated backfill. The source must raise the transient stop before the
    # page is ever yielded so the break never gets the chance.
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
    assert_raises(Xbookmark::TransientError) do
      source.bookmarks do |env|
        yielded << env
        break unless (env["meta"] || {})["next_token"]
      end
    end
    assert_empty yielded, "the transient stop fires before the cursorless page reaches the breaking consumer"
    assert_equal 1, session.quits
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

  it "yields an empty page for a malformed page but surfaces a transient error so backfill is not marked complete" do
    page = StubTimelinePage.new([bookmarks_body(ids: %w[1], cursor: "c1")])
    source = described_class.new(config: config, session: StubSession.new(page))
    # Crash normalization of a data-bearing page; the empty-envelope fallback
    # (a nil-payload Normalizer) has no entries to normalize, so it still works.
    Xbookmark::Browser::Normalizer.any_instance.stubs(:normalize_tweet_entry).raises("boom")

    yielded = []
    err = capture_stderr do
      assert_raises(Xbookmark::TransientError) { source.bookmarks { |env| yielded << env } }
    end

    assert_empty yielded, "the malformed page raises before it is yielded, so a breaking consumer cannot seal a truncated backfill"
    assert_match(/skipping a malformed bookmarks page/, err)
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

  it "raises TransientError when a captured Bookmarks body fails to parse (transient, not expired)" do
    # A clean settle (not stalled) plus a corrupt Bookmarks body must drive the
    # capture.failures? && !stalled branch of finish_walk → transient, not a
    # spurious re-login.
    page = StubTimelinePage.new(["{bad json"], url_kind: :bookmarks)
    source = described_class.new(config: config, session: StubSession.new(page))

    capture_stderr do
      assert_raises(Xbookmark::TransientError) { source.bookmarks { |_| flunk "no page expected" } }
    end
  end

  it "raises TransientError when a Bookmarks request is observed but never fills (transient, not expired)" do
    # A Bookmarks exchange whose body stays empty was observed but never filled —
    # transient, distinct from a session that issued no Bookmarks query at all.
    page = StubTimelinePage.new([""], url_kind: :bookmarks)
    source = described_class.new(config: config, session: StubSession.new(page))

    assert_raises(Xbookmark::TransientError) { source.bookmarks { |_| flunk "no page expected" } }
  end

  it "terminates at the iteration cap when the cursor never stops advancing" do
    page = StrictlyAdvancingPage.new
    source = described_class.new(config: config, session: StubSession.new(page))

    with_max_timeline_iterations(5) do
      assert_raises(Xbookmark::TransientError) { source.bookmarks { |_env| } }
    end
    assert_equal 5, page.scrolls, "the hard cap bounds the walk instead of letting it run unbounded"
  end

  it "raises SessionExpired when the bookmarks page redirects to login" do
    page = StubTimelinePage.new([bookmarks_body(ids: %w[1], cursor: "c1")],
                                current_url: "https://x.com/i/flow/login")
    session = StubSession.new(page)
    source = described_class.new(config: config, session: session)

    assert_raises(Xbookmark::Browser::SessionExpired) { source.bookmarks { |_| flunk "should not yield" } }
    assert_equal 1, session.quits
  end

  it "raises SessionExpired when the session expires mid-walk and drains go empty (no silent truncation)" do
    # pages>0, the settle is clean, and no capture failed — finish_walk alone
    # would seal this as a complete backfill. The post-loop guard re-check must
    # spot the mid-walk login redirect and demand re-login instead.
    page = MidWalkExpiringPage.new(bookmarks_body(ids: %w[1], cursor: "c1"))
    session = StubSession.new(page)
    source = described_class.new(config: config, session: session)

    yielded = []
    assert_raises(Xbookmark::Browser::SessionExpired) { source.bookmarks { |env| yielded << env } }
    assert_equal 1, yielded.size, "the page captured before the expiry is still yielded"
    assert_equal 1, session.quits
  end

  it "raises a transient error when a next page is observed but never fills after good pages (no silent truncation)" do
    # pages>0, a clean settle, and no capture failure — finish_walk's empty-rounds
    # guard alone would seal this as a complete backfill. But a next-page Bookmarks
    # request was observed whose body never filled (pending), so the unfetched tail
    # must be retried, not sealed. Covers the pages>0 counterpart to the pages==0
    # observed-but-never-filled case.
    good = StubXchg.new("https://x.com/i/api/graphql/abc/Bookmarks?p=0", bookmarks_body(ids: %w[1], cursor: "c1"), 0)
    pending = StubXchg.new("https://x.com/i/api/graphql/abc/Bookmarks?p=1", "", 1)
    page = GappyTimelinePage.new([[good], [good, pending]])
    session = StubSession.new(page)
    source = described_class.new(config: config, session: session)

    yielded = []
    error = assert_raises(Xbookmark::TransientError) { source.bookmarks { |env| yielded << env } }
    assert_equal 1, yielded.size, "the good page captured before the never-filled next page is still yielded"
    assert_match(/never filled|history tail may be incomplete/, error.message)
    assert_equal 1, session.quits
  end

  it "raises TransientError when the timeline walk exceeds its wall-clock budget" do
    # The iteration cap bounds scrolls, not elapsed time; a manual backfill must
    # also be bounded by the wall-clock deadline (the scheduled path has systemd).
    page = StubTimelinePage.new([bookmarks_body(ids: %w[1], cursor: "c1")])
    session = StubSession.new(page)
    source = described_class.new(config: config, session: session)
    # First call sets the deadline; the next clock read is already past it.
    source.stubs(:monotonic_now).returns(0, Xbookmark::Browser::Source::MAX_WALK_SECONDS + 1)

    error = assert_raises(Xbookmark::TransientError) { source.bookmarks { |_| } }
    assert_match(/wall-clock budget/, error.message)
    assert_equal 1, session.quits
  end

  it "raises a transient error when an unsettled walk stops on empty rounds (possible truncation)" do
    page = StubTimelinePage.new([bookmarks_body(ids: %w[1], cursor: "c1")], wait_raises: true)
    session = StubSession.new(page)
    source = described_class.new(config: config, session: session)

    yielded = []
    error = assert_raises(Xbookmark::TransientError) { source.bookmarks { |env| yielded << env } }
    assert_equal 1, yielded.size, "the good page is still yielded before the transient stop"
    assert_match(/history tail may be incomplete/, error.message)
    assert_equal 1, session.quits
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

  it "fails fast when constructed without a config" do
    assert_raises(ArgumentError) { described_class.new(config: nil) }
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

  it "returns the captured tweet from get_tweet even when the settle stalls" do
    # A slow single-tweet load whose body was nonetheless captured must still be
    # returned — the stall only matters when nothing was captured.
    page = StubTimelinePage.new([tweet_detail_body("777")], url_kind: :tweet, wait_raises: true)
    source = described_class.new(config: config, session: StubSession.new(page))

    payload = source.get_tweet("777")

    assert_equal "777", payload["data"]["id"]
  end

  it "raises TransientError from get_tweet when a stalled settle captured nothing" do
    # Nothing captured + a stalled settle is transient (retryable), not a
    # permanent SourceUnavailable.
    page = StubTimelinePage.new([JSON.generate({ "data" => {} })], url_kind: :bookmarks, wait_raises: true)
    source = described_class.new(config: config, session: StubSession.new(page))

    assert_raises(Xbookmark::TransientError) { source.get_tweet("404") }
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

    capture_stderr do
      assert_raises(Xbookmark::TransientError) { source.get_tweet("9") }
    end
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

  it "raises SessionExpired (not SourceUnavailable) from get_tweet when the session expires after settle" do
    # A clean settle that captured no tweet because X redirected to login *after*
    # the initial guard must surface as SessionExpired (re-login) — never the
    # permanent SourceUnavailable that a retry/resync would treat as a gone tweet.
    source = described_class.new(config: config, session: StubSession.new(TweetExpiringAfterSettlePage.new))

    assert_raises(Xbookmark::Browser::SessionExpired) { source.get_tweet("1") }
  end

  it "get_tweet returns the requested tweet, not a stray that drained last" do
    # The page fires an extra TweetResultByRestId/TweetDetail for a quoted or
    # hovercard tweet (999) that drains AFTER the focal tweet (555). The reverse
    # scan must still select 555 — returning whichever drained last would cache a
    # stray tweet under the wrong tweet_id.
    page = MultiTweetPage.new([tweet_detail_body("555"), tweet_detail_body("999")])
    source = described_class.new(config: config, session: StubSession.new(page))

    payload = source.get_tweet("555")
    assert_equal "555", payload["data"]["id"]
  end

  it "get_tweet returns the requested tweet even when a stray drained first" do
    page = MultiTweetPage.new([tweet_detail_body("999"), tweet_detail_body("555")])
    source = described_class.new(config: config, session: StubSession.new(page))

    payload = source.get_tweet("555")
    assert_equal "555", payload["data"]["id"]
  end

  it "get_tweet raises SourceUnavailable when only a stray tweet is captured on a clean settle" do
    # Only a stray (999) drained, never the focal 555, and the settle was clean —
    # the requested tweet is genuinely absent, so this is a permanent miss.
    page = MultiTweetPage.new([tweet_detail_body("999")])
    source = described_class.new(config: config, session: StubSession.new(page))

    assert_raises(Xbookmark::SourceUnavailable) { source.get_tweet("555") }
  end

  it "get_tweet treats a stray-only capture on a stalled settle as transient, not permanently gone" do
    # A stray (999) drained but the focal TweetDetail timed out (stalled settle):
    # the requested tweet may still exist, so this is a transient miss to retry —
    # not the permanent SourceUnavailable that would drop a still-existing tweet.
    page = MultiTweetPage.new([tweet_detail_body("999")], wait_raises: true)
    source = described_class.new(config: config, session: StubSession.new(page))

    assert_raises(Xbookmark::TransientError) { source.get_tweet("555") }
  end

  it "get_tweet treats a pending tweet body on a clean settle as transient, not permanently gone" do
    # The focal TweetDetail/TweetResultByRestId was observed but its body never
    # filled (empty => pending), and the settle was otherwise clean. The tweet may
    # still exist, so this is a retryable miss — not the permanent SourceUnavailable
    # that a retry/resync would treat as a gone tweet.
    page = StubTimelinePage.new([""], url_kind: :tweet)
    source = described_class.new(config: config, session: StubSession.new(page))

    assert_raises(Xbookmark::TransientError) { source.get_tweet("404") }
  end

  it "get_tweet treats a pending focal request behind a stray on a clean settle as transient" do
    # The focal 555 request is still pending (empty body) while only a stray (999)
    # drained, on an otherwise clean settle. matching_tweet_envelope finds no 555,
    # but the pending focal request makes this a retryable miss, not a gone tweet.
    page = MultiTweetPage.new(["", tweet_detail_body("999")])
    source = described_class.new(config: config, session: StubSession.new(page))

    assert_raises(Xbookmark::TransientError) { source.get_tweet("555") }
  end
end
