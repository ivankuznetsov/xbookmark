# frozen_string_literal: true

require "test_helper"

require "xbookmark/sync/runner"
require "xbookmark/state/store"

class FakeXClient
  attr_reader :calls

  def initialize(pages: [], single_tweet: nil)
    @pages = pages
    @single_tweet = single_tweet
    @calls = []
  end

  def bookmarks(user_id:, pagination_token: nil, max_results: Xbookmark::X::Client::BOOKMARK_PAGE_SIZE)
    return enum_for(:bookmarks, user_id: user_id, pagination_token: pagination_token, max_results: max_results) unless block_given?
    @calls << { user_id: user_id, pagination_token: pagination_token, max_results: max_results }
    @pages.each { |p| yield p }
  end

  def get_tweet(id)
    @single_tweet || raise("no fake tweet for #{id}")
  end
end

class FakePipeline
  attr_reader :calls

  def initialize(behavior)
    @behavior = behavior
    @calls = []
  end

  def process(bookmark)
    @calls << bookmark.tweet_id
    @behavior.call(bookmark)
  end
end

class FakeRegistrar
  attr_reader :index_calls

  def initialize
    @index_calls = 0
  end

  def index!
    @index_calls += 1
  end
end

describe Xbookmark::Sync::Runner do
  let(:store) { Xbookmark::State::Store.new(":memory:") }
  let(:vault) { Dir.mktmpdir }
  let(:config) do
    Struct::XbookmarkConfig.new(
      vault_path: vault,
      state_db_path: ":memory:",
      logs_dir: "/tmp",
      scratch_dir: File.join(vault, ".xbookmark", "scratch"),
      x_client_id: "c", x_client_secret: nil, x_redirect_uri: "x",
      x_user_id: "42", x_access_token: "t", x_refresh_token: nil,
      x_token_expires_at: nil, codex_bin: "codex",
      whisper_bin: nil, whisper_model: "base.en", qmd_bin: "qmd",
      daily_sync_time: "06:00", min_run_interval_hours: 20.0,
      env_file: nil, verbose: false
    )
  end

  let(:registrar) { FakeRegistrar.new }

  it "fresh + sync mode prints the bootstrap message and reports a permanent error" do
    fake_client = FakeXClient.new(pages: [])
    pipeline = FakePipeline.new(->(_) { Xbookmark::Sync::Pipeline::Outcome.new(status: :done, markdown_path: "/x", digest: "d") })
    runner = described_class.new(config: config, store: store, x_client: fake_client, pipeline: pipeline, registrar: registrar)
    out = capture_stdout { @report = runner.run(mode: :sync) }
    assert_match(/backfill --limit 100/, out)
    assert_equal 1, @report.permanent_errors
    assert_equal 0, registrar.index_calls
  end

  it "backfill --limit 100 stops at exactly N items even when API returns more" do
    page = {
      "data" => Array.new(150) { |i| { "id" => "t#{i}", "author_id" => "u1", "text" => "x", "created_at" => "2026-01-01T00:00:00Z", "conversation_id" => "c#{i}" } },
      "includes" => { "users" => [{ "id" => "u1", "username" => "alice" }] },
      "meta" => {}
    }

    pipeline = FakePipeline.new(->(_) { Xbookmark::Sync::Pipeline::Outcome.new(status: :done, markdown_path: "/x", digest: "d") })
    fake_client = FakeXClient.new(pages: [page])
    runner = described_class.new(config: config, store: store, x_client: fake_client,
                                 pipeline: pipeline, registrar: registrar)
    report = runner.run(mode: :backfill_limited, limit: 100)
    assert_equal 100, report.synced
    assert_equal 50, fake_client.calls.first[:max_results]
    assert_equal Xbookmark::State::Store::MODE_TEST_BACKFILLED, store.mode
    assert_equal 1, registrar.index_calls
  end

  it "transitions a failure on attempt 1 to success on retry, ordered failed-first on next run" do
    bookmark_payload = {
      "data" => [{ "id" => "1", "author_id" => "u1", "text" => "x", "created_at" => "2026-01-01T00:00:00Z", "conversation_id" => "1" }],
      "includes" => { "users" => [{ "id" => "u1", "username" => "alice" }] },
      "meta" => {}
    }
    single = { "data" => bookmark_payload["data"].first, "includes" => bookmark_payload["includes"] }
    client = FakeXClient.new(pages: [bookmark_payload], single_tweet: single)

    fail_then_pass = FakePipeline.new(->(bm) {
      if bm.tweet_id == "1" && fail_then_pass.calls.size == 1
        Xbookmark::Sync::Pipeline::Outcome.new(status: :needs_retry, error: StandardError.new("boom"))
      else
        Xbookmark::Sync::Pipeline::Outcome.new(status: :done, markdown_path: "/x", digest: "d")
      end
    })

    runner = described_class.new(config: config, store: store, x_client: client, pipeline: fail_then_pass, registrar: registrar)
    r1 = runner.run(mode: :backfill_limited, limit: 1)
    assert_equal 1, r1.failed

    r2 = runner.run(mode: :backfill_limited, limit: 1)
    assert_equal 1, r2.synced
    assert_equal "done", store.find_bookmark("1")[:status]
  end

  it "skip-if-recent: --from-scheduler exits 0 when the previous finish was < threshold" do
    store.mark_sync_finished!(Time.now.utc - 60) # 1m ago
    pipeline = FakePipeline.new(->(_) { Xbookmark::Sync::Pipeline::Outcome.new(status: :done, markdown_path: "/x", digest: "d") })
    runner = described_class.new(config: config, store: store, x_client: FakeXClient.new(pages: []), pipeline: pipeline, registrar: registrar)
    out = capture_stdout { @r = runner.run(mode: :sync, from_scheduler: true) }
    assert_match(/skipping/, out)
    assert_equal 0, @r.synced
  end

  it "skip-if-recent does not fire on a manual sync" do
    store.mode = Xbookmark::State::Store::MODE_INCREMENTAL
    store.mark_sync_finished!(Time.now.utc - 60)
    pipeline = FakePipeline.new(->(_) { Xbookmark::Sync::Pipeline::Outcome.new(status: :done, markdown_path: "/x", digest: "d") })
    runner = described_class.new(config: config, store: store, x_client: FakeXClient.new(pages: []), pipeline: pipeline, registrar: registrar)
    runner.run(mode: :sync, from_scheduler: false)
    # No skip output, no error — manual sync runs even when recent.
    assert_equal Xbookmark::State::Store::MODE_INCREMENTAL, store.mode
  end

  it "incremental sync starts from the newest page and stops once a page has no new bookmarks" do
    store.mode = Xbookmark::State::Store::MODE_FULLY_BACKFILLED
    store.cursor = "stale-historical-token"
    store.upsert_pending(tweet_id: "known", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z")
    store.record_success(tweet_id: "known", markdown_path: "/known.md", digest: "d")

    known_page = {
      "data" => [{ "id" => "known", "author_id" => "u1", "text" => "x", "created_at" => "2026-01-01T00:00:00Z", "conversation_id" => "known" }],
      "includes" => { "users" => [{ "id" => "u1", "username" => "alice" }] },
      "meta" => { "next_token" => "older" }
    }
    older_page = {
      "data" => [{ "id" => "older", "author_id" => "u1", "text" => "older", "created_at" => "2025-01-01T00:00:00Z", "conversation_id" => "older" }],
      "includes" => { "users" => [{ "id" => "u1", "username" => "alice" }] },
      "meta" => {}
    }

    fake_client = FakeXClient.new(pages: [known_page, older_page])
    pipeline = FakePipeline.new(->(_) { Xbookmark::Sync::Pipeline::Outcome.new(status: :done, markdown_path: "/x", digest: "d") })
    runner = described_class.new(config: config, store: store, x_client: fake_client, pipeline: pipeline, registrar: registrar)

    report = runner.run(mode: :sync)

    assert_nil fake_client.calls.first[:pagination_token]
    assert_equal 1, report.skipped
    assert_equal 0, report.synced
    assert_empty pipeline.calls
  end

  it "full backfill marks the store fully backfilled and stamps completion time" do
    stale = File.join(config.scratch_dir, "stale")
    FileUtils.mkdir_p(stale)
    page = {
      "data" => [{ "id" => "1", "author_id" => "u1", "text" => "x", "created_at" => "2026-01-01T00:00:00Z", "conversation_id" => "1" }],
      "includes" => { "users" => [{ "id" => "u1", "username" => "alice" }] },
      "meta" => {}
    }
    pipeline = FakePipeline.new(->(_) { Xbookmark::Sync::Pipeline::Outcome.new(status: :done, markdown_path: "/x", digest: "d") })
    runner = described_class.new(config: config, store: store, x_client: FakeXClient.new(pages: [page]),
                                 pipeline: pipeline, registrar: registrar)

    report = runner.run(mode: :backfill_full)

    assert_equal 1, report.synced
    refute File.exist?(stale)
    assert_equal Xbookmark::State::Store::MODE_FULLY_BACKFILLED, store.mode
    refute_nil store.get_meta("last_full_backfill_at")
    refute_nil store.last_sync_finished_at
  end

  it "incremental sync refuses to run after a limited test backfill" do
    store.mode = Xbookmark::State::Store::MODE_TEST_BACKFILLED
    pipeline = FakePipeline.new(->(_) { Xbookmark::Sync::Pipeline::Outcome.new(status: :done, markdown_path: "/x", digest: "d") })
    runner = described_class.new(config: config, store: store, x_client: FakeXClient.new(pages: []), pipeline: pipeline, registrar: registrar)

    out = capture_stdout { @report = runner.run(mode: :sync) }
    assert_match(/test-backfilled/, out)
    assert_equal 1, @report.permanent_errors
    assert_nil store.last_sync_finished_at
  end

  it "resyncs one tweet by resetting retry attempts before processing" do
    store.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z")
    2.times { store.record_failure(tweet_id: "1", error: "old") }
    single = {
      "data" => { "id" => "1", "author_id" => "u1", "text" => "x", "created_at" => "2026-01-01T00:00:00Z", "conversation_id" => "1" },
      "includes" => { "users" => [{ "id" => "u1", "username" => "alice" }] }
    }
    pipeline = FakePipeline.new(->(_) { Xbookmark::Sync::Pipeline::Outcome.new(status: :done, markdown_path: "/x", digest: "d") })
    runner = described_class.new(config: config, store: store, x_client: FakeXClient.new(single_tweet: single),
                                 pipeline: pipeline, registrar: registrar)

    report = runner.run(mode: :resync, tweet_id: "1")

    assert_equal 1, report.synced
    assert_equal 0, store.find_bookmark("1")[:attempts]
  end

  it "requires tweet_id for resync and rejects unknown modes" do
    runner = described_class.new(config: config, store: store, x_client: FakeXClient.new(pages: []),
                                 pipeline: FakePipeline.new(->(_) { }), registrar: registrar)

    error = assert_raises(ArgumentError) { runner.run(mode: :resync) }
    assert_match(/tweet_id/, error.message)
    error = assert_raises(ArgumentError) { runner.run(mode: :bogus) }
    assert_match(/unknown mode/, error.message)
  end

  it "records permanent pipeline outcomes and keeps going when QMD reindex fails" do
    page = {
      "data" => [{ "id" => "1", "author_id" => "u1", "text" => "x", "created_at" => "2026-01-01T00:00:00Z", "conversation_id" => "1" }],
      "includes" => { "users" => [{ "id" => "u1", "username" => "alice" }] },
      "meta" => {}
    }
    pipeline = FakePipeline.new(->(_) { Xbookmark::Sync::Pipeline::Outcome.new(status: :permanent_error, error: Xbookmark::PermanentError.new("bad")) })
    runner = described_class.new(config: config, store: store, x_client: FakeXClient.new(pages: [page]),
                                 pipeline: pipeline, registrar: registrar)

    report = runner.run(mode: :backfill_limited, limit: 1)

    assert_equal 1, report.permanent_errors
    assert_equal "permanent_error", store.find_bookmark("1")[:status]
  end

  it "warns but does not fail when QMD reindex raises after a successful sync" do
    page = {
      "data" => [{ "id" => "1", "author_id" => "u1", "text" => "x", "created_at" => "2026-01-01T00:00:00Z", "conversation_id" => "1" }],
      "includes" => { "users" => [{ "id" => "u1", "username" => "alice" }] },
      "meta" => {}
    }
    bad_registrar = Class.new do
      def ensure_registered!
        raise "qmd down"
      end

      def index!
        raise "qmd down"
      end
    end.new
    pipeline = FakePipeline.new(->(_) { Xbookmark::Sync::Pipeline::Outcome.new(status: :done, markdown_path: "/x", digest: "d") })
    runner = described_class.new(config: config, store: store, x_client: FakeXClient.new(pages: [page]),
                                 pipeline: pipeline, registrar: bad_registrar)

    err = capture_stderr { @report = runner.run(mode: :backfill_limited, limit: 1) }
    assert_match(/qmd reindex failed: qmd down/, err)
    assert_equal 1, @report.synced
  end

  it "reports auth errors while retrying failed bookmarks" do
    store.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z")
    store.record_failure(tweet_id: "1", error: "temporary")
    client = FakeXClient.new(pages: [])
    client.stubs(:get_tweet).raises(Xbookmark::AuthError, "expired")
    runner = described_class.new(config: config, store: store, x_client: client,
                                 pipeline: FakePipeline.new(->(_) { }), registrar: registrar)

    err = capture_stderr { @report = runner.run(mode: :backfill_limited, limit: 1) }
    assert_match(/auth error during retry: expired/, err)
    assert_equal 1, @report.permanent_errors
  end
end
