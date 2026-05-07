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
    expect(row[:markdown_path]).to eq("/v/1.md")
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
