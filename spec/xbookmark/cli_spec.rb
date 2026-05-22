# frozen_string_literal: true

require "xbookmark/cli"

RSpec.describe Xbookmark::CLI do
  it "exposes a `version` command" do
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

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end
end
