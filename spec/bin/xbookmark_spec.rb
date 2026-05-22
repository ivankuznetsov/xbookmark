# frozen_string_literal: true

require "xbookmark/cli"

RSpec.describe "bin/xbookmark" do
  it "loads the CLI and starts it with ARGV" do
    original_argv = ARGV.dup
    ARGV.replace(["--version"])
    expect(Xbookmark::CLI).to receive(:start).with(ARGV)

    load File.expand_path("../../bin/xbookmark", __dir__)
  ensure
    ARGV.replace(original_argv)
  end

  it "starts the CLI with empty ARGV when first-run setup is already configured" do
    original_argv = ARGV.dup
    ARGV.replace([])
    allow(Xbookmark::CLI::Setup).to receive(:first_run_configured?).and_return(true)
    expect(Xbookmark::CLI).to receive(:start).with(ARGV)

    load File.expand_path("../../bin/xbookmark", __dir__)
  ensure
    ARGV.replace(original_argv)
  end
end
