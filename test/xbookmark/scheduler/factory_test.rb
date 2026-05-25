# frozen_string_literal: true

require "test_helper"

require "xbookmark/scheduler/factory"

describe Xbookmark::Scheduler::Factory do
  let(:config) { stub("config") }

  it "returns Systemd on Linux" do
    stub_platform_linux
    assert_kind_of Xbookmark::Scheduler::Systemd, described_class.build(config: config)
  end

  it "returns Launchd on macOS" do
    stub_platform_macos
    assert_kind_of Xbookmark::Scheduler::Launchd, described_class.build(config: config)
  end

  it "raises UnsupportedPlatform otherwise" do
    Xbookmark::Paths.stubs(:linux?).returns(false)
    Xbookmark::Paths.stubs(:macos?).returns(false)
    assert_raises(Xbookmark::UnsupportedPlatform) { described_class.build(config: config) }
  end
end
