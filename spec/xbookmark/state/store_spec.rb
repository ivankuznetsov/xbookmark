# frozen_string_literal: true

require "xbookmark/state/store"

RSpec.describe Xbookmark::State::Store do
  let(:store) { described_class.new(":memory:") }

  it "applies migrations and starts in 'fresh' mode" do
    expect(store.mode).to eq(Xbookmark::State::Store::MODE_FRESH)
  end

  it "returns nil for an unknown bookmark" do
    expect(store.find_bookmark("nope")).to be_nil
  end

  it "records a failure (increments attempts, sets last_error) then a success (clears it)" do
    store.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z")

    store.record_failure(tweet_id: "1", error: "boom")
    row = store.find_bookmark("1")
    expect(row[:attempts]).to eq(1)
    expect(row[:status]).to eq("needs_retry")
    expect(row[:last_error]).to eq("boom")

    store.record_success(tweet_id: "1", markdown_path: "/v/1.md", digest: "abc")
    row = store.find_bookmark("1")
    expect(row[:status]).to eq("done")
    expect(row[:last_error]).to be_nil
    expect(row[:attempts]).to eq(0)
    expect(row[:markdown_path]).to eq("/v/1.md")
  end

  it "resets attempts on success so a later failure starts from zero again" do
    store.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z")
    2.times { store.record_failure(tweet_id: "1", error: "boom") }
    expect(store.find_bookmark("1")[:attempts]).to eq(2)

    store.record_success(tweet_id: "1", markdown_path: "/v/1.md", digest: "abc")
    expect(store.find_bookmark("1")[:attempts]).to eq(0)

    store.record_failure(tweet_id: "1", error: "later transient")
    row = store.find_bookmark("1")
    expect(row[:attempts]).to eq(1)
    expect(row[:status]).to eq("needs_retry")
  end

  it "promotes to permanent_error after 3 failed attempts" do
    store.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z")
    3.times { store.record_failure(tweet_id: "1", error: "boom") }
    expect(store.find_bookmark("1")[:status]).to eq("permanent_error")
  end

  it "bookmarks_to_retry returns failed rows ordered by attempts ASC then bookmarked_at DESC" do
    store.upsert_pending(tweet_id: "1", author_handle: "a", bookmarked_at: "2026-01-01T00:00:00Z")
    store.upsert_pending(tweet_id: "2", author_handle: "b", bookmarked_at: "2026-01-02T00:00:00Z")
    store.upsert_pending(tweet_id: "3", author_handle: "c", bookmarked_at: "2026-01-03T00:00:00Z")

    store.record_failure(tweet_id: "1", error: "x")
    store.record_failure(tweet_id: "1", error: "x")
    store.record_failure(tweet_id: "2", error: "x")
    store.record_failure(tweet_id: "3", error: "x")

    ids = store.bookmarks_to_retry(limit: 10).map { |r| r[:tweet_id] }
    # 1 has 2 attempts and would be permanent already, so check fresh failures first
    # tweet_id 2 and 3 each have 1 attempt; 3 is more recent
    expect(ids.first(2)).to eq(%w[3 2])
  end

  it "tracks the X pagination cursor" do
    store.cursor = "abc"
    expect(store.cursor).to eq("abc")
  end

  it "tracks sync timestamps and full backfill metadata" do
    time = Time.utc(2026, 1, 1, 12, 0, 0)
    store.mark_sync_started!(time)
    store.mark_sync_finished!(time)
    store.mark_full_backfill_complete!(time)

    expect(store.get_meta("last_sync_at")).to eq(time.iso8601)
    expect(store.last_sync_finished_at).to eq(time)
    expect(store.get_meta("last_full_backfill_at")).to eq(time.iso8601)
  end

  it "round-trips meta keys" do
    store.set_meta("foo", "bar")
    expect(store.get_meta("foo")).to eq("bar")
  end

  it "ensure_registered/upsert_page is idempotent and updates digest when given" do
    store.upsert_page(kind: "topic", slug: "ozempic", path: "topics/ozempic.md")
    page = store.find_page("topic", "ozempic")
    expect(page[:path]).to eq("topics/ozempic.md")

    t = Time.now.utc
    store.upsert_page(kind: "topic", slug: "ozempic", path: "topics/ozempic.md",
                      summary_input_digest: "deadbeef", summarized_at: t)
    page = store.find_page("topic", "ozempic")
    expect(page[:summary_input_digest]).to eq("deadbeef")
  end

  it "keeps existing page digest when an update omits a new digest and lists topic/entity slugs" do
    store.upsert_page(kind: "topic", slug: "ozempic", path: "topics/ozempic.md",
                      summary_input_digest: "digest", summarized_at: Time.utc(2026, 1, 1))
    store.upsert_page(kind: "topic", slug: "ozempic", path: "topics/ozempic-new.md")
    store.upsert_page(kind: "entity", slug: "novo", path: "entities/novo.md")
    store.upsert_page(kind: "author", slug: "alice", path: "authors/alice.md")

    page = store.find_page("topic", "ozempic")
    expect(page[:path]).to eq("topics/ozempic-new.md")
    expect(page[:summary_input_digest]).to eq("digest")
    expect(store.all_topic_slugs).to contain_exactly("ozempic", "novo")
  end

  it "converts non-string timestamps when inserting pending bookmarks" do
    store.upsert_pending(tweet_id: "time", author_handle: "alice", bookmarked_at: Time.utc(2026, 1, 1))

    expect(store.find_bookmark("time")[:bookmarked_at]).to eq("2026-01-01T00:00:00Z")

    parsed = double(:timestamp, to_s: "2026-02-03T04:05:06Z")
    store.upsert_pending(tweet_id: "parsed", author_handle: "alice", bookmarked_at: parsed)
    expect(store.find_bookmark("parsed")[:bookmarked_at]).to eq("2026-02-03T04:05:06Z")
  end

  it "persists to disk and re-opens cleanly" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "state.db")
      s1 = described_class.new(path)
      s1.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z")
      s1.close
      s2 = described_class.new(path)
      expect(s2.find_bookmark("1")[:author_handle]).to eq("alice")
      s2.close
    end
  end
end
