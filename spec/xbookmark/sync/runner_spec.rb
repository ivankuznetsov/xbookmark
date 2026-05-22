# frozen_string_literal: true

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

RSpec.describe Xbookmark::Sync::Runner do
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
    expect { @report = runner.run(mode: :sync) }.to output(/backfill --limit 100/).to_stdout
    expect(@report.permanent_errors).to eq(1)
    expect(registrar.index_calls).to eq(0)
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
    expect(report.synced).to eq(100)
    expect(fake_client.calls.first[:max_results]).to eq(50)
    expect(store.mode).to eq(Xbookmark::State::Store::MODE_TEST_BACKFILLED)
    expect(registrar.index_calls).to eq(1)
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
    expect(r1.failed).to eq(1)

    r2 = runner.run(mode: :backfill_limited, limit: 1)
    expect(r2.synced).to eq(1)
    expect(store.find_bookmark("1")[:status]).to eq("done")
  end

  it "skip-if-recent: --from-scheduler exits 0 when the previous finish was < threshold" do
    store.mark_sync_finished!(Time.now.utc - 60) # 1m ago
    pipeline = FakePipeline.new(->(_) { Xbookmark::Sync::Pipeline::Outcome.new(status: :done, markdown_path: "/x", digest: "d") })
    runner = described_class.new(config: config, store: store, x_client: FakeXClient.new(pages: []), pipeline: pipeline, registrar: registrar)
    expect { @r = runner.run(mode: :sync, from_scheduler: true) }.to output(/skipping/).to_stdout
    expect(@r.synced).to eq(0)
  end

  it "skip-if-recent does not fire on a manual sync" do
    store.mode = Xbookmark::State::Store::MODE_INCREMENTAL
    store.mark_sync_finished!(Time.now.utc - 60)
    pipeline = FakePipeline.new(->(_) { Xbookmark::Sync::Pipeline::Outcome.new(status: :done, markdown_path: "/x", digest: "d") })
    runner = described_class.new(config: config, store: store, x_client: FakeXClient.new(pages: []), pipeline: pipeline, registrar: registrar)
    runner.run(mode: :sync, from_scheduler: false)
    # No skip output, no error — manual sync runs even when recent.
    expect(store.mode).to eq(Xbookmark::State::Store::MODE_INCREMENTAL)
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

    expect(fake_client.calls.first[:pagination_token]).to be_nil
    expect(report.skipped).to eq(1)
    expect(report.synced).to eq(0)
    expect(pipeline.calls).to be_empty
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

    expect(report.synced).to eq(1)
    expect(File.exist?(stale)).to be(false)
    expect(store.mode).to eq(Xbookmark::State::Store::MODE_FULLY_BACKFILLED)
    expect(store.get_meta("last_full_backfill_at")).not_to be_nil
    expect(store.last_sync_finished_at).not_to be_nil
  end

  it "incremental sync refuses to run after a limited test backfill" do
    store.mode = Xbookmark::State::Store::MODE_TEST_BACKFILLED
    pipeline = FakePipeline.new(->(_) { Xbookmark::Sync::Pipeline::Outcome.new(status: :done, markdown_path: "/x", digest: "d") })
    runner = described_class.new(config: config, store: store, x_client: FakeXClient.new(pages: []), pipeline: pipeline, registrar: registrar)

    expect { @report = runner.run(mode: :sync) }.to output(/test-backfilled/).to_stdout
    expect(@report.permanent_errors).to eq(1)
    expect(store.last_sync_finished_at).to be_nil
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

    expect(report.synced).to eq(1)
    expect(store.find_bookmark("1")[:attempts]).to eq(0)
  end

  it "requires tweet_id for resync and rejects unknown modes" do
    runner = described_class.new(config: config, store: store, x_client: FakeXClient.new(pages: []),
                                 pipeline: FakePipeline.new(->(_) { }), registrar: registrar)

    expect { runner.run(mode: :resync) }.to raise_error(ArgumentError, /tweet_id/)
    expect { runner.run(mode: :bogus) }.to raise_error(ArgumentError, /unknown mode/)
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

    expect(report.permanent_errors).to eq(1)
    expect(store.find_bookmark("1")[:status]).to eq("permanent_error")
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

    expect { @report = runner.run(mode: :backfill_limited, limit: 1) }
      .to output(/qmd reindex failed: qmd down/).to_stderr
    expect(@report.synced).to eq(1)
  end

  it "reports auth errors while retrying failed bookmarks" do
    store.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z")
    store.record_failure(tweet_id: "1", error: "temporary")
    client = FakeXClient.new(pages: [])
    allow(client).to receive(:get_tweet).and_raise(Xbookmark::AuthError, "expired")
    runner = described_class.new(config: config, store: store, x_client: client,
                                 pipeline: FakePipeline.new(->(_) { }), registrar: registrar)

    expect { @report = runner.run(mode: :backfill_limited, limit: 1) }
      .to output(/auth error during retry: expired/).to_stderr
    expect(@report.permanent_errors).to eq(1)
  end
end
