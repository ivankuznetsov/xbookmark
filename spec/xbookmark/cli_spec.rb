# frozen_string_literal: true

require "xbookmark/cli"

RSpec.describe Xbookmark::CLI do
  it "exposes a `version` command" do
    out = capture_stdout { described_class.start(%w[version]) }
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

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end
end
