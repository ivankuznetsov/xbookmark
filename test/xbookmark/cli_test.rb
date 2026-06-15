# frozen_string_literal: true

require "test_helper"

require "xbookmark/cli"
require "xbookmark/qmd/registrar"
require "xbookmark/qmd/searcher"
require "xbookmark/scheduler/base"
require "xbookmark/scheduler/factory"
require "xbookmark/sync/runner"
require "xbookmark/transcribe/whisper"
require "xbookmark/x/auth"
require "xbookmark/x/client"

describe Xbookmark::CLI do
  FakeReport = Struct.new(:failed, :permanent_errors, :source_errors, :message, keyword_init: true) do
    def source_errors
      self[:source_errors] || 0
    end

    def to_s
      message
    end
  end

  def test_config(overrides = {})
    Struct::XbookmarkConfig.new({
      vault_path: "/tmp/wiki",
      state_db_path: ":memory:",
      logs_dir: "/tmp/logs",
      scratch_dir: "/tmp/wiki/.xbookmark/scratch",
      x_client_id: "client",
      x_client_secret: nil,
      x_redirect_uri: "http://127.0.0.1:7799/callback",
      x_user_id: "42",
      x_access_token: "token",
      x_refresh_token: nil,
      x_token_expires_at: 123,
      codex_bin: "codex",
      whisper_bin: nil,
      whisper_model: "base.en",
      qmd_bin: "qmd",
      daily_sync_time: "06:00",
      min_run_interval_hours: 20.0,
      aux_summaries: false,
      env_file: "/tmp/.env",
      verbose: false
    }.merge(overrides))
  end

  it "exposes a `version` command" do
    assert described_class.exit_on_failure?
    out = capture_stdout { described_class.start(%w[version]) }
    assert_equal Xbookmark::VERSION, out.strip
  end

  it "exposes --version for setup scripts" do
    out = capture_stdout { described_class.start(%w[--version]) }
    assert_equal Xbookmark::VERSION, out.strip
  end

  it "lists all top-level subcommands in --help" do
    out = capture_stdout { described_class.start(%w[help]) }
    %w[auth backfill sync find doctor install resync].each do |cmd|
      assert_match(/^\s*\S+\s#{cmd}\b/, out)
    end
  end

  it "advertises the bookmark wiki path override" do
    out = capture_stdout { described_class.start(%w[help]) }
    assert_includes out, "--wiki"
    assert_includes out, "Override the bookmark wiki path"
  end

  it "shows find help instead of searching for --help" do
    out = capture_stdout { described_class.start(%w[find --help]) }
    assert_includes out, "find QUERY"
    assert_includes out, "Search the bookmark wiki via QMD"
  end

  it "passes --wiki to top-level command handlers" do
    fake = stub(execute: nil)
    Xbookmark::CLI::Doctor.expects(:new).with do |args, options|
      assert_equal [], args
      assert_equal "/bookmark/wiki", options[:wiki]
      assert_nil options[:vault]
      true
    end.returns(fake)

    capture_stdout { described_class.start(%w[doctor --wiki /bookmark/wiki]) }
  end

  it "keeps --vault as a legacy alias for top-level command handlers" do
    fake = stub(execute: nil)
    Xbookmark::CLI::Doctor.expects(:new).with do |args, options|
      assert_equal [], args
      assert_nil options[:wiki]
      assert_equal "/legacy/vault", options[:vault]
      true
    end.returns(fake)

    capture_stdout { described_class.start(%w[doctor --vault /legacy/vault]) }
  end

  it "passes --wiki to auth subcommands" do
    config = Struct.new(:x_access_token, :x_token_expires_at).new("", nil)
    Xbookmark::Config.expects(:load).with(wiki_override: "/auth/wiki", vault_override: nil, verbose: false).returns(config)

    assert_raises(SystemExit) do
      capture_stdout { described_class.start(%w[auth status --wiki /auth/wiki]) }
    end
  end

  it "runs first-run setup from the installed executable when invoked without args on a tty" do
    bin_path = File.expand_path("../../bin/xbookmark", __dir__)
    input = StringIO.new
    def input.tty?; true; end

    Xbookmark::CLI::Setup.stubs(:first_run_configured?).returns(false)
    Xbookmark::CLI::Setup.expects(:first_run_check!).returns(0)
    TOPLEVEL_BINDING.receiver.expects(:exit).with(0).returns(nil)
    described_class.stubs(:start).with(ARGV).returns(nil)

    old_argv = ARGV.dup
    old_stdin = $stdin
    ARGV.replace([])
    $stdin = input
    load bin_path
  ensure
    ARGV.replace(old_argv) if old_argv
    $stdin = old_stdin if old_stdin
  end

  it "routes top-level command bodies to the concrete command groups" do
    Xbookmark::CLI::Sync.expects(:new).with { |args, options| args == [] && options.is_a?(Hash) }.returns(stub(backfill_run: nil))
    capture_stdout { described_class.start(%w[backfill --limit 3]) }

    Xbookmark::CLI::Sync.expects(:new).with { |args, options| args == [] && options.is_a?(Hash) }.returns(stub(sync_run: nil))
    capture_stdout { described_class.start(%w[sync --from-scheduler]) }

    Xbookmark::CLI::Sync.expects(:new).with { |args, options| args == [] && options.is_a?(Hash) }.returns(stub(resync_run: nil))
    capture_stdout { described_class.start(%w[resync 123]) }

    Xbookmark::CLI::Find.expects(:new).with { |args, options| args == [] && options.is_a?(Hash) }.returns(stub(find_run: nil))
    capture_stdout { described_class.start(%w[find ozempic dose]) }

    Xbookmark::CLI::Install.expects(:new).with { |args, options| args == [] && options.is_a?(Hash) }.returns(stub(execute: nil))
    capture_stdout { described_class.start(%w[install --dry-run]) }
  end

  it "runs auth login and reports the token destination" do
    config = test_config
    result = Xbookmark::X::Auth::AuthResult.new(env_file: "/tmp/.env", access_token: "a", refresh_token: "r", expires_at: 1)
    auth = stub(login: result)
    Xbookmark::Config.stubs(:load).returns(config)
    Xbookmark::X::Auth.expects(:new).with(config).returns(auth)

    err = capture_stderr { Xbookmark::CLI::Auth.start(%w[login]) }

    assert_includes err, "Tokens written to /tmp/.env"
  end

  it "reports auth login failures without a stack trace" do
    config = test_config
    auth = stub
    auth.stubs(:login).raises(Xbookmark::AuthError, "OAuth callback timed out after 600s")
    Xbookmark::Config.stubs(:load).returns(config)
    Xbookmark::X::Auth.expects(:new).with(config).returns(auth)

    old_stderr = $stderr
    $stderr = StringIO.new
    error = assert_raises(SystemExit) { Xbookmark::CLI::Auth.start(%w[login]) }

    assert_equal 1, error.status
    assert_includes $stderr.string, "[xbookmark] OAuth callback timed out after 600s"
    assert_includes $stderr.string, "Run: xbookmark auth login"
    refute_includes $stderr.string, "xbookmark/cli/auth.rb"
  ensure
    $stderr = old_stderr
  end

  it "redacts token-like values from auth login failures" do
    config = test_config
    auth = stub
    auth.stubs(:login).raises(
      Xbookmark::AuthError,
      'Token exchange failed (400): {"access_token":"ACCESSSECRET12345678901234567890"}'
    )
    Xbookmark::Config.stubs(:load).returns(config)
    Xbookmark::X::Auth.expects(:new).with(config).returns(auth)

    old_stderr = $stderr
    $stderr = StringIO.new
    error = assert_raises(SystemExit) { Xbookmark::CLI::Auth.start(%w[login]) }

    assert_equal 1, error.status
    assert_includes $stderr.string, "[REDACTED]"
    refute_includes $stderr.string, "ACCESSSECRET"
  ensure
    $stderr = old_stderr
  end

  it "reports transient auth login failures as retryable" do
    config = test_config
    auth = stub
    auth.stubs(:login).raises(Xbookmark::TransientAuthError, "Token exchange transport failed: timeout")
    Xbookmark::Config.stubs(:load).returns(config)
    Xbookmark::X::Auth.expects(:new).with(config).returns(auth)

    old_stderr = $stderr
    $stderr = StringIO.new
    error = assert_raises(SystemExit) { Xbookmark::CLI::Auth.start(%w[login]) }

    assert_equal 2, error.status
    assert_includes $stderr.string, "[xbookmark] Token exchange transport failed: timeout"
    assert_includes $stderr.string, "X token login is temporarily unavailable. Retry auth login later."
    refute_includes $stderr.string, "Run: xbookmark auth login"
  ensure
    $stderr = old_stderr
  end

  it "prints auth status without exiting when a token is present" do
    Xbookmark::Config.stubs(:load).returns(test_config(x_access_token: "token", x_token_expires_at: 2_000_000_000))
    Time.stubs(:now).returns(Time.at(1_000_000_000))

    out = capture_stdout { Xbookmark::CLI::Auth.start(%w[status]) }

    assert_includes out, "Logged in. Token expires at: 2000000000 (2033-05-18T03:33:20Z)"
  end

  it "exits when auth status sees an expired access token" do
    Xbookmark::Config.stubs(:load).returns(test_config(x_access_token: "token", x_refresh_token: "refresh",
                                                       x_token_expires_at: 999))
    Time.stubs(:now).returns(Time.at(1_000))

    old_stdout = $stdout
    $stdout = StringIO.new
    error = assert_raises(SystemExit) { Xbookmark::CLI::Auth.start(%w[status]) }

    assert_equal 1, error.status
    assert_includes $stdout.string, "Access token expired at: 999 (1970-01-01T00:16:39Z)"
    assert_includes $stdout.string, "Refresh token present. Run: xbookmark auth refresh"
  ensure
    $stdout = old_stdout
  end

  it "treats auth tokens expiring exactly now as expired" do
    Xbookmark::Config.stubs(:load).returns(test_config(x_access_token: "token", x_refresh_token: "refresh",
                                                       x_token_expires_at: 1_000))
    Time.stubs(:now).returns(Time.at(1_000))

    old_stdout = $stdout
    $stdout = StringIO.new
    error = assert_raises(SystemExit) { Xbookmark::CLI::Auth.start(%w[status]) }

    assert_equal 1, error.status
    assert_includes $stdout.string, "Access token expired at: 1000 (1970-01-01T00:16:40Z)"
    assert_includes $stdout.string, "Refresh token present. Run: xbookmark auth refresh"
  ensure
    $stdout = old_stdout
  end

  it "points expired auth status at login when no refresh token exists" do
    Xbookmark::Config.stubs(:load).returns(test_config(x_access_token: "token", x_refresh_token: nil,
                                                       x_token_expires_at: 999))
    Time.stubs(:now).returns(Time.at(1_000))

    old_stdout = $stdout
    $stdout = StringIO.new
    error = assert_raises(SystemExit) { Xbookmark::CLI::Auth.start(%w[status]) }

    assert_equal 1, error.status
    assert_includes $stdout.string, "No refresh token. Run: xbookmark auth login"
  ensure
    $stdout = old_stdout
  end

  it "refreshes auth tokens on demand" do
    config = test_config
    result = Xbookmark::X::Auth::AuthResult.new(env_file: "/tmp/.env", access_token: "a", refresh_token: "r",
                                                expires_at: 2_000_000_000)
    auth = stub(refresh!: result)
    Xbookmark::Config.expects(:load).with(wiki_override: "/auth/wiki", vault_override: nil, verbose: true).returns(config)
    Xbookmark::X::Auth.expects(:new).with(config).returns(auth)

    err = capture_stderr { Xbookmark::CLI::Auth.start(%w[refresh --wiki /auth/wiki --verbose]) }

    assert_includes err, "Refreshed. Tokens written to /tmp/.env"
    assert_includes err, "Token expires at: 2000000000 (2033-05-18T03:33:20Z)"
  end

  it "reports refresh failures without a stack trace" do
    config = test_config
    auth = stub
    auth.stubs(:refresh!).raises(Xbookmark::AuthError, "Token refresh failed")
    Xbookmark::Config.stubs(:load).returns(config)
    Xbookmark::X::Auth.expects(:new).with(config).returns(auth)

    old_stderr = $stderr
    $stderr = StringIO.new
    error = assert_raises(SystemExit) { Xbookmark::CLI::Auth.start(%w[refresh]) }

    assert_equal 1, error.status
    assert_includes $stderr.string, "[xbookmark] Token refresh failed"
    assert_includes $stderr.string, "Run: xbookmark auth login"
  ensure
    $stderr = old_stderr
  end

  it "reports transient refresh failures as retryable" do
    config = test_config
    auth = stub
    auth.stubs(:refresh!).raises(Xbookmark::TransientAuthError, "Token refresh transport failed: timeout")
    Xbookmark::Config.stubs(:load).returns(config)
    Xbookmark::X::Auth.expects(:new).with(config).returns(auth)

    old_stderr = $stderr
    $stderr = StringIO.new
    error = assert_raises(SystemExit) { Xbookmark::CLI::Auth.start(%w[refresh]) }

    assert_equal 2, error.status
    assert_includes $stderr.string, "[xbookmark] Token refresh transport failed: timeout"
    assert_includes $stderr.string, "X token refresh is temporarily unavailable. Retry later."
    refute_includes $stderr.string, "Run: xbookmark auth login"
  ensure
    $stderr = old_stderr
  end

  it "redacts token-like values from refresh failures" do
    config = test_config
    auth = stub
    auth.stubs(:refresh!).raises(
      Xbookmark::AuthError,
      'Token refresh failed (400): {"access_token":"ACCESSSECRET12345678901234567890",' \
      '"refresh_token":"REFRESHSECRET12345678901234567890"}'
    )
    Xbookmark::Config.stubs(:load).returns(config)
    Xbookmark::X::Auth.expects(:new).with(config).returns(auth)

    old_stderr = $stderr
    $stderr = StringIO.new
    error = assert_raises(SystemExit) { Xbookmark::CLI::Auth.start(%w[refresh]) }

    assert_equal 1, error.status
    assert_includes $stderr.string, "[REDACTED]"
    refute_includes $stderr.string, "ACCESSSECRET"
    refute_includes $stderr.string, "REFRESHSECRET"
  ensure
    $stderr = old_stderr
  end

  it "runs backfill, sync, and resync with real stores and runner wiring" do
    config = test_config
    Xbookmark::Config.stubs(:load).returns(config)
    Xbookmark::X::Client.stubs(:new).returns(stub)

    reports = [
      FakeReport.new(failed: 0, permanent_errors: 0, message: "backfilled"),
      FakeReport.new(failed: 0, permanent_errors: 0, message: "synced"),
      FakeReport.new(failed: 0, permanent_errors: 0, message: "resynced")
    ]
    runner = mock("runner")
    runner.stubs(:run).returns(*reports)
    Xbookmark::Sync::Runner.expects(:new).times(3).returns(runner)

    assert_includes capture_stdout { Xbookmark::CLI::Sync.new([], { limit: 5 }).backfill_run }, "backfilled"
    assert_includes capture_stdout { Xbookmark::CLI::Sync.new([], { "from-scheduler": true }).sync_run }, "synced"
    assert_includes capture_stdout { Xbookmark::CLI::Sync.new([], {}).resync_run("123") }, "resynced"
  end

  it "exits with a non-zero status when sync reports failures" do
    Xbookmark::Config.stubs(:load).returns(test_config)
    runner = stub(run: FakeReport.new(failed: 1, permanent_errors: 0, message: "failed"))
    Xbookmark::Sync::Runner.stubs(:new).returns(runner)

    error = assert_raises(SystemExit) do
      capture_stdout { Xbookmark::CLI::Sync.new([], {}).sync_run }
    end
    assert_equal 2, error.status
  end

  it "keeps scheduled source outages from failing the service but fails manual sync" do
    Xbookmark::Config.stubs(:load).returns(test_config)
    Xbookmark::Sync::Runner.stubs(:new).returns(
      stub(run: FakeReport.new(failed: 0, permanent_errors: 0, source_errors: 1, message: "source blocked"))
    )

    assert_includes capture_stdout { Xbookmark::CLI::Sync.new([], { "from-scheduler": true }).sync_run }, "source blocked"

    error = assert_raises(SystemExit) do
      capture_stdout { Xbookmark::CLI::Sync.new([], {}).sync_run }
    end
    assert_equal 1, error.status
  end

  it "still fails scheduled sync when local pipeline work fails" do
    Xbookmark::Config.stubs(:load).returns(test_config)
    Xbookmark::Sync::Runner.stubs(:new).returns(
      stub(run: FakeReport.new(failed: 1, permanent_errors: 0, source_errors: 1, message: "failed and source blocked"))
    )

    error = assert_raises(SystemExit) do
      capture_stdout { Xbookmark::CLI::Sync.new([], { "from-scheduler": true }).sync_run }
    end
    assert_equal 1, error.status
  end

  it "prints find results with scores and snippets and reports empty matches" do
    Xbookmark::Config.stubs(:load).returns(test_config)
    searcher = mock("searcher")
    Xbookmark::Qmd::Searcher.stubs(:new).returns(searcher)

    searcher.stubs(:search).with("query", limit: 2)
      .returns([{ path: "/wiki/a.md", score: 0.9123, snippet: "matched text" }])
    out = capture_stdout { Xbookmark::CLI::Find.new([], { limit: 2 }).find_run("query") }
    assert_includes out, "1. [0.91] /wiki/a.md"
    assert_includes out, "matched text"

    searcher.stubs(:search).with("missing", limit: 20).returns([])
    assert_includes capture_stdout { Xbookmark::CLI::Find.new([], {}).find_run("missing") }, "No matches for: missing"
  end

  it "runs doctor checks for binaries, whisper, platform, and auth state" do
    Dir.mktmpdir do |dir|
      %w[codex qmd ffmpeg].each do |name|
        path = File.join(dir, name)
        File.write(path, "#!/bin/sh\n")
        File.chmod(0o755, path)
      end
      Xbookmark::Paths.stubs(:macos?).returns(false)
      Xbookmark::Paths.stubs(:linux?).returns(true)
      Xbookmark::Config.stubs(:load).returns(test_config(whisper_bin: File.join(dir, "whisper-cli"), x_access_token: ""))
      Xbookmark::Transcribe::Whisper.stubs(:detect).returns(nil)

      out = with_env(ENV.to_h.merge("PATH" => dir)) do
        capture_stdout { Xbookmark::CLI::Doctor.new([], {}).execute }
      end

      assert_includes out, "platform: Linux"
      assert_includes out, "codex: ok"
      assert_includes out, "whisper: NOT FOUND"
      assert_includes out, "X auth: NOT logged in"
    end
  end

  it "reports macOS doctor checks with missing binaries, detected whisper, and present token" do
    Xbookmark::Paths.stubs(:macos?).returns(true)
    Xbookmark::Paths.stubs(:linux?).returns(false)
    Xbookmark::Config.stubs(:load).returns(test_config(x_access_token: "token", x_token_expires_at: nil))
    Xbookmark::Transcribe::Whisper.stubs(:detect).returns("/usr/local/bin/whisper-cli")

    out = with_env(ENV.to_h.merge("PATH" => "/no/such/dir")) do
      capture_stdout { Xbookmark::CLI::Doctor.new([], {}).execute }
    end

    assert_includes out, "platform: macOS"
    assert_includes out, "scheduler backend: launchd"
    assert_includes out, "codex: NOT FOUND"
    assert_includes out, "whisper: ok (/usr/local/bin/whisper-cli)"
    assert_includes out, "X auth: token present (expires_at=unknown)"
  end

  it "runs scheduler install, dry-run install, and uninstall flows" do
    config = test_config
    scheduler = mock("scheduler")
    registrar = mock("registrar")
    codex_config = mock("codex config")
    Xbookmark::Config.stubs(:load).returns(config)
    Xbookmark::Scheduler::Factory.stubs(:build).returns(scheduler)
    Xbookmark::Qmd::Registrar.stubs(:new).returns(registrar)
    Xbookmark::CodexConfig.stubs(:new).returns(codex_config)

    codex_config.expects(:remove_service_tier_override!).once.returns(false)
    scheduler.expects(:install).with(time: "07:30", dry_run: false).returns(true)
    registrar.expects(:ensure_registered!).returns(true)
    Xbookmark::CLI::Install.new([], { time: "07:30", "dry-run": false }).execute

    scheduler.expects(:install).with(time: "06:00", dry_run: true).returns(true)
    registrar.expects(:ensure_registered!).never
    Xbookmark::CLI::Install.new([], { "dry-run": true }).execute

    scheduler.expects(:uninstall).with(time: "06:00", dry_run: false).returns(true)
    Xbookmark::CLI::Install.new([], { uninstall: true, "dry-run": false }).execute
  end

  it "continues install when codex service tier cleanup fails" do
    config = test_config
    scheduler = mock("scheduler")
    registrar = mock("registrar")
    codex_config = mock("codex config")
    Xbookmark::Config.stubs(:load).returns(config)
    Xbookmark::Scheduler::Factory.stubs(:build).returns(scheduler)
    Xbookmark::Qmd::Registrar.stubs(:new).returns(registrar)
    Xbookmark::CodexConfig.stubs(:new).returns(codex_config)
    codex_config.stubs(:remove_service_tier_override!).raises(StandardError, "bad config")

    scheduler.expects(:install).with(time: "06:00", dry_run: false).returns(true)
    registrar.expects(:ensure_registered!).returns(true)

    err = capture_stderr { Xbookmark::CLI::Install.new([], { "dry-run": false }).execute }
    assert_includes err, "codex service_tier setup failed: bad config"
  end

  it "routes setup and uninstall commands" do
    setup = stub(execute: 0)
    Xbookmark::CLI::Setup.expects(:new).with { |args, options| args == [] && options.is_a?(Hash) }.returns(setup)
    capture_stdout { described_class.start(%w[setup]) }

    successful_uninstall = stub(execute: 0)
    Xbookmark::CLI::Uninstall.expects(:new).with { |args, options| args == [] && options.is_a?(Hash) }.returns(successful_uninstall)
    capture_stdout { described_class.start(%w[uninstall --purge --yes]) }

    failed_uninstall = stub(execute: 1)
    Xbookmark::CLI::Uninstall.expects(:new).with { |args, options| args == [] && options.is_a?(Hash) }.returns(failed_uninstall)
    error = assert_raises(SystemExit) do
      capture_stdout { described_class.start(%w[uninstall --purge --yes]) }
    end
    assert_equal 1, error.status
  end

  it "runs the installed executable first-run hook and normal dispatch paths" do
    bin_path = File.expand_path("../../bin/xbookmark", __dir__)
    input = StringIO.new
    def input.tty?; true; end

    old_argv = ARGV.dup
    old_stdin = $stdin
    ARGV.replace([])
    $stdin = input
    Xbookmark::CLI::Setup.stubs(:first_run_configured?).returns(false)
    Xbookmark::CLI::Setup.stubs(:first_run_check!).returns(0)
    TOPLEVEL_BINDING.receiver.expects(:exit).with(0).returns(nil)
    described_class.expects(:start).with(ARGV).returns(nil)

    load bin_path
  ensure
    ARGV.replace(old_argv) if old_argv
    $stdin = old_stdin if old_stdin
  end
end
