# frozen_string_literal: true

require "test_helper"

require "xbookmark/cli"

describe "bin/xbookmark" do
  it "dispatches through the real CLI when arguments are present" do
    original_argv = ARGV.dup
    ARGV.replace(["--version"])

    out = capture_stdout { load File.expand_path("../../bin/xbookmark", __dir__) }

    assert_equal Xbookmark::VERSION, out.strip
  ensure
    ARGV.replace(original_argv)
  end

  it "loads the CLI and starts it with ARGV" do
    original_argv = ARGV.dup
    ARGV.replace(["--version"])
    Xbookmark::CLI.expects(:start).with(ARGV)

    load File.expand_path("../../bin/xbookmark", __dir__)
  ensure
    ARGV.replace(original_argv)
  end

  it "starts the CLI with empty ARGV when first-run setup is already configured" do
    original_argv = ARGV.dup
    ARGV.replace([])
    Xbookmark::CLI::Setup.stubs(:first_run_configured?).returns(true)
    Xbookmark::CLI.expects(:start).with(ARGV)

    load File.expand_path("../../bin/xbookmark", __dir__)
  ensure
    ARGV.replace(original_argv)
  end
end
