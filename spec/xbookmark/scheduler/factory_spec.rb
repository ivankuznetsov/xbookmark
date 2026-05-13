# frozen_string_literal: true

require "xbookmark/scheduler/factory"

RSpec.describe Xbookmark::Scheduler::Factory do
  let(:config) { double(:config) }

  it "returns Systemd on Linux" do
    stub_platform_linux
    expect(described_class.build(config: config)).to be_a(Xbookmark::Scheduler::Systemd)
  end

  it "returns Launchd on macOS" do
    stub_platform_macos
    expect(described_class.build(config: config)).to be_a(Xbookmark::Scheduler::Launchd)
  end

  it "raises UnsupportedPlatform otherwise" do
    allow(Xbookmark::Paths).to receive(:linux?).and_return(false)
    allow(Xbookmark::Paths).to receive(:macos?).and_return(false)
    expect { described_class.build(config: config) }.to raise_error(Xbookmark::UnsupportedPlatform)
  end
end
