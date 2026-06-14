# frozen_string_literal: true

require "test_helper"

require "xbookmark/state/store"

describe Xbookmark::State::Store do
  let(:store) { described_class.new(":memory:") }

  it "applies migrations and starts in 'fresh' mode" do
    assert_equal Xbookmark::State::Store::MODE_FRESH, store.mode
  end

  it "migrates existing v1 databases to cache source payloads" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "state.db")
      db = SQLite3::Database.new(path)
      db.execute_batch(<<~SQL)
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
        INSERT INTO meta(key, value) VALUES ('schema_version', '1');
        CREATE TABLE bookmarks (
          tweet_id TEXT PRIMARY KEY,
          author_handle TEXT NOT NULL,
          bookmarked_at TEXT NOT NULL,
          ingested_at TEXT,
          status TEXT NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0,
          last_error TEXT,
          markdown_path TEXT,
          enrichment_digest TEXT
        );
        CREATE TABLE pages (
          kind TEXT NOT NULL,
          slug TEXT NOT NULL,
          path TEXT NOT NULL,
          last_summarized_at TEXT,
          summary_input_digest TEXT,
          PRIMARY KEY (kind, slug)
        );
      SQL
      db.close

      migrated = described_class.new(path)
      migrated.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z",
                              payload: { "data" => [{ "id" => "1" }] })

      assert_equal "2", migrated.get_meta("schema_version")
      assert_equal [{ "id" => "1" }], migrated.payload_for("1")["data"]
      migrated.close
    end
  end

  it "returns nil for an unknown bookmark" do
    assert_nil store.find_bookmark("nope")
  end

  it "records a failure (increments attempts, sets last_error) then a success (clears it)" do
    store.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z")

    store.record_failure(tweet_id: "1", error: "boom")
    row = store.find_bookmark("1")
    assert_equal 1, row[:attempts]
    assert_equal "needs_retry", row[:status]
    assert_equal "boom", row[:last_error]

    store.record_success(tweet_id: "1", markdown_path: "/v/1.md", digest: "abc")
    row = store.find_bookmark("1")
    assert_equal "done", row[:status]
    assert_nil row[:last_error]
    assert_equal 0, row[:attempts]
    assert_equal "/v/1.md", row[:markdown_path]
  end

  it "stores payloads without resetting an existing bookmark status" do
    payload = { "data" => [{ "id" => "1", "text" => "hello" }], "includes" => {}, "meta" => {} }
    store.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z")
    store.record_success(tweet_id: "1", markdown_path: "/v/1.md", digest: "abc")
    store.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z",
                         payload: payload)

    row = store.find_bookmark("1")
    assert_equal "done", row[:status]
    assert_equal payload, store.payload_for("1")
  end

  it "treats corrupt cached payload JSON as absent" do
    store.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z",
                         payload: { "data" => [] })
    store.instance_variable_get(:@db).execute("UPDATE bookmarks SET payload_json = ? WHERE tweet_id = ?", ["{bad", "1"])

    assert_nil store.payload_for("1")
  end

  it "resets attempts on success so a later failure starts from zero again" do
    store.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z")
    2.times { store.record_failure(tweet_id: "1", error: "boom") }
    assert_equal 2, store.find_bookmark("1")[:attempts]

    store.record_success(tweet_id: "1", markdown_path: "/v/1.md", digest: "abc")
    assert_equal 0, store.find_bookmark("1")[:attempts]

    store.record_failure(tweet_id: "1", error: "later transient")
    row = store.find_bookmark("1")
    assert_equal 1, row[:attempts]
    assert_equal "needs_retry", row[:status]
  end

  it "promotes to permanent_error after 3 failed attempts" do
    store.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z")
    3.times { store.record_failure(tweet_id: "1", error: "boom") }
    assert_equal "permanent_error", store.find_bookmark("1")[:status]
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
    assert_equal %w[3 2], ids.first(2)
  end

  it "bookmarks_to_process includes pending and retryable rows" do
    store.upsert_pending(tweet_id: "pending", author_handle: "a", bookmarked_at: "2026-01-03T00:00:00Z")
    store.upsert_pending(tweet_id: "retry", author_handle: "b", bookmarked_at: "2026-01-02T00:00:00Z")
    store.upsert_pending(tweet_id: "done", author_handle: "c", bookmarked_at: "2026-01-01T00:00:00Z")
    store.record_failure(tweet_id: "retry", error: "x")
    store.record_success(tweet_id: "done", markdown_path: "/v/done.md", digest: "abc")

    assert_equal %w[pending retry], store.bookmarks_to_process(limit: 10).map { |row| row[:tweet_id] }
  end

  it "tracks the X pagination cursor" do
    store.cursor = "abc"
    assert_equal "abc", store.cursor
  end

  it "tracks sync timestamps and full backfill metadata" do
    time = Time.utc(2026, 1, 1, 12, 0, 0)
    store.mark_sync_started!(time)
    store.mark_sync_finished!(time)
    store.mark_full_backfill_complete!(time)

    assert_equal time.iso8601, store.get_meta("last_sync_at")
    assert_equal time, store.last_sync_finished_at
    assert_equal time.iso8601, store.get_meta("last_full_backfill_at")
  end

  it "round-trips meta keys" do
    store.set_meta("foo", "bar")
    assert_equal "bar", store.get_meta("foo")
  end

  it "ensure_registered/upsert_page is idempotent and updates digest when given" do
    store.upsert_page(kind: "topic", slug: "ozempic", path: "topics/ozempic.md")
    page = store.find_page("topic", "ozempic")
    assert_equal "topics/ozempic.md", page[:path]

    t = Time.now.utc
    store.upsert_page(kind: "topic", slug: "ozempic", path: "topics/ozempic.md",
                      summary_input_digest: "deadbeef", summarized_at: t)
    page = store.find_page("topic", "ozempic")
    assert_equal "deadbeef", page[:summary_input_digest]
  end

  it "keeps existing page digest when an update omits a new digest and lists topic/entity slugs" do
    store.upsert_page(kind: "topic", slug: "ozempic", path: "topics/ozempic.md",
                      summary_input_digest: "digest", summarized_at: Time.utc(2026, 1, 1))
    store.upsert_page(kind: "topic", slug: "ozempic", path: "topics/ozempic-new.md")
    store.upsert_page(kind: "entity", slug: "novo", path: "entities/novo.md")
    store.upsert_page(kind: "author", slug: "alice", path: "authors/alice.md")

    page = store.find_page("topic", "ozempic")
    assert_equal "topics/ozempic-new.md", page[:path]
    assert_equal "digest", page[:summary_input_digest]
    assert_equal %w[novo ozempic], store.all_topic_slugs.sort
  end

  it "converts non-string timestamps when inserting pending bookmarks" do
    store.upsert_pending(tweet_id: "time", author_handle: "alice", bookmarked_at: Time.utc(2026, 1, 1))

    assert_equal "2026-01-01T00:00:00Z", store.find_bookmark("time")[:bookmarked_at]

    parsed = stub("timestamp", to_s: "2026-02-03T04:05:06Z")
    store.upsert_pending(tweet_id: "parsed", author_handle: "alice", bookmarked_at: parsed)
    assert_equal "2026-02-03T04:05:06Z", store.find_bookmark("parsed")[:bookmarked_at]
  end

  it "persists to disk and re-opens cleanly" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "state.db")
      s1 = described_class.new(path)
      s1.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z")
      s1.close
      s2 = described_class.new(path)
      assert_equal "alice", s2.find_bookmark("1")[:author_handle]
      s2.close
    end
  end
end
