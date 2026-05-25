# frozen_string_literal: true

require "xbookmark/cli"
require "xbookmark/qmd/registrar"
require "xbookmark/qmd/searcher"
require "xbookmark/scheduler/base"
require "xbookmark/scheduler/factory"
require "xbookmark/sync/runner"
require "xbookmark/transcribe/whisper"
require "xbookmark/x/auth"
require "xbookmark/x/client"

RSpec.describe Xbookmark::CLI do
  FakeReport = Struct.new(:failed, :permanent_errors, :message, keyword_init: true) do
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
    expect(described_class.exit_on_failure?).to be(true)
    out = capture_stdout { described_class.start(%w[version]) }
    expect(out.strip).to eq(Xbookmark::VERSION)
  end

  it "exposes --version for setup scripts" do
    out = capture_stdout { described_class.start(%w[--version]) }
    expect(out.strip).to eq(Xbookmark::VERSION)
  end

  it "lists all top-level subcommands in --help" do
    out = capture_stdout { described_class.start(%w[help]) }
    %w[auth backfill sync find doctor install resync].each do |cmd|
      expect(out).to match(/^\s*\S+\s#{cmd}\b/)
    end
  end

  it "advertises the bookmark wiki path override" do
    out = capture_stdout { described_class.start(%w[help]) }
    expect(out).to include("--wiki")
    expect(out).to include("Override the bookmark wiki path")
  end

  it "shows find help instead of searching for --help" do
    out = capture_stdout { described_class.start(%w[find --help]) }
    expect(out).to include("find QUERY")
    expect(out).to include("Search the bookmark wiki via QMD")
  end

  it "passes --wiki to top-level command handlers" do
    fake = instance_double(Xbookmark::CLI::Doctor, execute: nil)
    expect(Xbookmark::CLI::Doctor).to receive(:new) do |args, options|
      expect(args).to eq([])
      expect(options[:wiki]).to eq("/bookmark/wiki")
      expect(options[:vault]).to be_nil
      fake
    end

    capture_stdout { described_class.start(%w[doctor --wiki /bookmark/wiki]) }
  end

  it "keeps --vault as a legacy alias for top-level command handlers" do
    fake = instance_double(Xbookmark::CLI::Doctor, execute: nil)
    expect(Xbookmark::CLI::Doctor).to receive(:new) do |args, options|
      expect(args).to eq([])
      expect(options[:wiki]).to be_nil
      expect(options[:vault]).to eq("/legacy/vault")
      fake
    end

    capture_stdout { described_class.start(%w[doctor --vault /legacy/vault]) }
  end

  it "passes --wiki to auth subcommands" do
    config = Struct.new(:x_access_token, :x_token_expires_at).new("", nil)
    expect(Xbookmark::Config).to receive(:load).with(wiki_override: "/auth/wiki", vault_override: nil, verbose: false).and_return(config)

    expect do
      capture_stdout { described_class.start(%w[auth status --wiki /auth/wiki]) }
    end.to raise_error(SystemExit)
  end

  it "runs first-run setup from the installed executable when invoked without args on a tty" do
    bin_path = File.expand_path("../../bin/xbookmark", __dir__)
    input = StringIO.new
    def input.tty?; true; end

    allow(Xbookmark::CLI::Setup).to receive(:first_run_configured?).and_return(false)
    expect(Xbookmark::CLI::Setup).to receive(:first_run_check!).and_return(0)
    expect(described_class).not_to receive(:start)

    old_argv = ARGV.dup
    old_stdin = $stdin
    ARGV.replace([])
    $stdin = input
    expect { load bin_path }.to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
  ensure
    ARGV.replace(old_argv) if old_argv
    $stdin = old_stdin if old_stdin
  end

  it "routes top-level command bodies to the concrete command groups" do
    expect(Xbookmark::CLI::Sync).to receive(:new).with([], kind_of(Hash)).and_return(instance_double(Xbookmark::CLI::Sync, backfill_run: nil))
    capture_stdout { described_class.start(%w[backfill --limit 3]) }

    expect(Xbookmark::CLI::Sync).to receive(:new).with([], kind_of(Hash)).and_return(instance_double(Xbookmark::CLI::Sync, sync_run: nil))
    capture_stdout { described_class.start(%w[sync --from-scheduler]) }

    expect(Xbookmark::CLI::Sync).to receive(:new).with([], kind_of(Hash)).and_return(instance_double(Xbookmark::CLI::Sync, resync_run: nil))
    capture_stdout { described_class.start(%w[resync 123]) }

    expect(Xbookmark::CLI::Find).to receive(:new).with([], kind_of(Hash)).and_return(instance_double(Xbookmark::CLI::Find, find_run: nil))
    capture_stdout { described_class.start(%w[find ozempic dose]) }

    expect(Xbookmark::CLI::Install).to receive(:new).with([], kind_of(Hash)).and_return(instance_double(Xbookmark::CLI::Install, execute: nil))
    capture_stdout { described_class.start(%w[install --dry-run]) }
  end

  it "runs auth login and reports the token destination" do
    config = test_config
    result = Xbookmark::X::Auth::AuthResult.new(env_file: "/tmp/.env", access_token: "a", refresh_token: "r", expires_at: 1)
    auth = instance_double(Xbookmark::X::Auth, login: result)
    allow(Xbookmark::Config).to receive(:load).and_return(config)
    expect(Xbookmark::X::Auth).to receive(:new).with(config).and_return(auth)

    err = capture_stderr { Xbookmark::CLI::Auth.start(%w[login]) }

    expect(err).to include("Tokens written to /tmp/.env")
  end

  it "prints auth status without exiting when a token is present" do
    allow(Xbookmark::Config).to receive(:load).and_return(test_config(x_access_token: "token", x_token_expires_at: 42))

    out = capture_stdout { Xbookmark::CLI::Auth.start(%w[status]) }

    expect(out).to include("Logged in. Token expires at: 42")
  end

  it "runs backfill, sync, and resync with real stores and runner wiring" do
    config = test_config
    allow(Xbookmark::Config).to receive(:load).and_return(config)
    allow(Xbookmark::X::Client).to receive(:new).and_call_original

    reports = [
      FakeReport.new(failed: 0, permanent_errors: 0, message: "backfilled"),
      FakeReport.new(failed: 0, permanent_errors: 0, message: "synced"),
      FakeReport.new(failed: 0, permanent_errors: 0, message: "resynced")
    ]
    runner = instance_double(Xbookmark::Sync::Runner)
    allow(runner).to receive(:run) { reports.shift }
    expect(Xbookmark::Sync::Runner).to receive(:new).exactly(3).times.and_return(runner)

    expect(capture_stdout { Xbookmark::CLI::Sync.new([], { limit: 5 }).backfill_run }).to include("backfilled")
    expect(capture_stdout { Xbookmark::CLI::Sync.new([], { "from-scheduler": true }).sync_run }).to include("synced")
    expect(capture_stdout { Xbookmark::CLI::Sync.new([], {}).resync_run("123") }).to include("resynced")
  end

  it "exits with a non-zero status when sync reports failures" do
    allow(Xbookmark::Config).to receive(:load).and_return(test_config)
    runner = instance_double(Xbookmark::Sync::Runner, run: FakeReport.new(failed: 1, permanent_errors: 0, message: "failed"))
    allow(Xbookmark::Sync::Runner).to receive(:new).and_return(runner)

    expect do
      capture_stdout { Xbookmark::CLI::Sync.new([], {}).sync_run }
    end.to raise_error(SystemExit) { |error| expect(error.status).to eq(2) }
  end

  it "prints find results with scores and snippets and reports empty matches" do
    allow(Xbookmark::Config).to receive(:load).and_return(test_config)
    searcher = instance_double(Xbookmark::Qmd::Searcher)
    allow(Xbookmark::Qmd::Searcher).to receive(:new).and_return(searcher)

    allow(searcher).to receive(:search).with("query", limit: 2)
      .and_return([{ path: "/wiki/a.md", score: 0.9123, snippet: "matched text" }])
    out = capture_stdout { Xbookmark::CLI::Find.new([], { limit: 2 }).find_run("query") }
    expect(out).to include("1. [0.91] /wiki/a.md")
    expect(out).to include("matched text")

    allow(searcher).to receive(:search).with("missing", limit: 20).and_return([])
    expect(capture_stdout { Xbookmark::CLI::Find.new([], {}).find_run("missing") })
      .to include("No matches for: missing")
  end

  it "runs doctor checks for binaries, whisper, platform, and auth state" do
    Dir.mktmpdir do |dir|
      %w[codex qmd ffmpeg].each do |name|
        path = File.join(dir, name)
        File.write(path, "#!/bin/sh\n")
        File.chmod(0o755, path)
      end
      stub_const("ENV", ENV.to_hash.merge("PATH" => dir))
      allow(Xbookmark::Paths).to receive(:macos?).and_return(false)
      allow(Xbookmark::Paths).to receive(:linux?).and_return(true)
      allow(Xbookmark::Config).to receive(:load).and_return(test_config(whisper_bin: File.join(dir, "whisper-cli"), x_access_token: ""))
      allow(Xbookmark::Transcribe::Whisper).to receive(:detect).and_return(nil)

      out = capture_stdout { Xbookmark::CLI::Doctor.new([], {}).execute }

      expect(out).to include("platform: Linux")
      expect(out).to include("codex: ok")
      expect(out).to include("whisper: NOT FOUND")
      expect(out).to include("X auth: NOT logged in")
    end
  end

  it "reports macOS doctor checks with missing binaries, detected whisper, and present token" do
    stub_const("ENV", ENV.to_hash.merge("PATH" => "/no/such/dir"))
    allow(Xbookmark::Paths).to receive(:macos?).and_return(true)
    allow(Xbookmark::Paths).to receive(:linux?).and_return(false)
    allow(Xbookmark::Config).to receive(:load).and_return(test_config(x_access_token: "token", x_token_expires_at: nil))
    allow(Xbookmark::Transcribe::Whisper).to receive(:detect).and_return("/usr/local/bin/whisper-cli")

    out = capture_stdout { Xbookmark::CLI::Doctor.new([], {}).execute }

    expect(out).to include("platform: macOS")
    expect(out).to include("scheduler backend: launchd")
    expect(out).to include("codex: NOT FOUND")
    expect(out).to include("whisper: ok (/usr/local/bin/whisper-cli)")
    expect(out).to include("X auth: token present (expires_at=unknown)")
  end

  it "runs scheduler install, dry-run install, and uninstall flows" do
    config = test_config
    scheduler = instance_double(Xbookmark::Scheduler::Base)
    registrar = instance_double(Xbookmark::Qmd::Registrar)
    codex_config = instance_double(Xbookmark::CodexConfig)
    allow(Xbookmark::Config).to receive(:load).and_return(config)
    allow(Xbookmark::Scheduler::Factory).to receive(:build).and_return(scheduler)
    allow(Xbookmark::Qmd::Registrar).to receive(:new).and_return(registrar)
    allow(Xbookmark::CodexConfig).to receive(:new).and_return(codex_config)

    expect(codex_config).to receive(:remove_service_tier_override!).once
    expect(scheduler).to receive(:install).with(time: "07:30", dry_run: false)
    expect(registrar).to receive(:ensure_registered!)
    Xbookmark::CLI::Install.new([], { time: "07:30", "dry-run": false }).execute

    expect(scheduler).to receive(:install).with(time: "06:00", dry_run: true)
    expect(registrar).not_to receive(:ensure_registered!)
    Xbookmark::CLI::Install.new([], { "dry-run": true }).execute

    expect(scheduler).to receive(:uninstall).with(time: "06:00", dry_run: false)
    Xbookmark::CLI::Install.new([], { uninstall: true, "dry-run": false }).execute
  end

  it "routes setup and uninstall commands" do
    setup = instance_double(Xbookmark::CLI::Setup, execute: 0)
    expect(Xbookmark::CLI::Setup).to receive(:new).with([], kind_of(Hash)).and_return(setup)
    capture_stdout { described_class.start(%w[setup]) }

    successful_uninstall = instance_double(Xbookmark::CLI::Uninstall, execute: 0)
    expect(Xbookmark::CLI::Uninstall).to receive(:new).with([], kind_of(Hash)).and_return(successful_uninstall)
    capture_stdout { described_class.start(%w[uninstall --purge --yes]) }

    failed_uninstall = instance_double(Xbookmark::CLI::Uninstall, execute: 1)
    expect(Xbookmark::CLI::Uninstall).to receive(:new).with([], kind_of(Hash)).and_return(failed_uninstall)
    expect do
      capture_stdout { described_class.start(%w[uninstall --purge --yes]) }
    end.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
  end

  it "runs the installed executable first-run hook and normal dispatch paths" do
    bin_path = File.expand_path("../../bin/xbookmark", __dir__)
    input = StringIO.new
    def input.tty?; true; end

    old_argv = ARGV.dup
    old_stdin = $stdin
    ARGV.replace([])
    $stdin = input
    allow(Xbookmark::CLI::Setup).to receive(:first_run_configured?).and_return(false)
    allow(Xbookmark::CLI::Setup).to receive(:first_run_check!).and_return(0)
    expect(TOPLEVEL_BINDING.receiver).to receive(:exit).with(0)
    expect(described_class).to receive(:start).with(ARGV)

    load bin_path
  ensure
    ARGV.replace(old_argv) if old_argv
    $stdin = old_stdin if old_stdin
  end

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end

  def capture_stderr
    old = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = old
  end
end
