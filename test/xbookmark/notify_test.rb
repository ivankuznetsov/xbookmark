# frozen_string_literal: true

require "test_helper"
require "xbookmark/notify"

describe Xbookmark::Notify do
  it "builds a notify-send command on Linux" do
    stub_platform_linux
    assert_equal ["notify-send", "Title", "Body"], described_class.command_for("Title", "Body")
  end

  it "builds an osascript command on macOS and escapes embedded quotes" do
    stub_platform_macos
    argv = described_class.command_for("a \"quoted\" title", "the body")
    assert_equal "osascript", argv[0]
    assert_equal "-e", argv[1]
    assert_includes argv[2], "display notification"
    assert_includes argv[2], "with title"
    assert_includes argv[2], '\\"quoted\\"'
  end

  it "escapes backslashes before quotes so a trailing backslash cannot break out" do
    stub_platform_macos
    argv = described_class.command_for("title", "ends\\")
    # The lone trailing backslash is doubled so it can't escape the closing quote.
    assert_includes argv[2], %(notification "ends\\\\")
  end

  it "produces no command on an unsupported platform" do
    Xbookmark::Paths.stubs(:macos?).returns(false)
    Xbookmark::Paths.stubs(:linux?).returns(false)
    assert_nil described_class.command_for("t", "b")
  end

  it "dispatches the command and reports success" do
    stub_platform_linux
    described_class.expects(:invoke).with(["notify-send", "Title", "Body"]).returns(true)
    assert described_class.deliver("Title", "Body")
  end

  it "returns false without dispatching on an unsupported platform" do
    Xbookmark::Paths.stubs(:macos?).returns(false)
    Xbookmark::Paths.stubs(:linux?).returns(false)
    refute described_class.deliver("t", "b")
  end

  it "swallows a missing-binary error instead of raising" do
    stub_platform_linux
    described_class.stubs(:invoke).raises(Errno::ENOENT, "notify-send")
    refute described_class.deliver("t", "b")
  end

  it "spawns the notifier detached so it never blocks the run" do
    assert_equal true, described_class.invoke(["true"])
  end
end
