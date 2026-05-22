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

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end
end
