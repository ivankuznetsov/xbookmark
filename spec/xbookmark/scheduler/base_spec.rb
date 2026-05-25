# frozen_string_literal: true

require "xbookmark/scheduler/base"

RSpec.describe Xbookmark::Scheduler::Base do
  subject(:scheduler) { described_class.new(config: Object.new) }

  it "requires concrete scheduler subclasses to implement public actions" do
    expect { scheduler.install(time: "06:00") }.to raise_error(NotImplementedError)
    expect { scheduler.uninstall }.to raise_error(NotImplementedError)
    expect { scheduler.status }.to raise_error(NotImplementedError)
  end

  it "parses valid scheduler times and rejects malformed times" do
    expect(scheduler.send(:parse_time, "03:05")).to eq([3, 5])
    expect { scheduler.send(:parse_time, "3:5") }.to raise_error(Xbookmark::Error, /invalid time/)
  end

  it "prefers the local checkout executable" do
    expect(scheduler.xbookmark_bin).to end_with("/bin/xbookmark")
  end

  it "falls back to an installed gem executable when the checkout executable is absent" do
    Dir.mktmpdir do |dir|
      gem_bin = File.join(dir, "xbookmark")
      File.write(gem_bin, "#!/bin/sh\n")
      File.chmod(0o755, gem_bin)
      local = File.expand_path("../../../bin/xbookmark", __dir__)

      allow(File).to receive(:executable?).and_call_original
      allow(File).to receive(:executable?).with(local).and_return(false)
      allow(Gem).to receive(:bin_path).with("xbookmark", "xbookmark").and_return(gem_bin)

      expect(scheduler.xbookmark_bin).to eq(gem_bin)
    end
  end

  it "falls back to PATH and then the local path when no executable can be found" do
    Dir.mktmpdir do |dir|
      path_bin = File.join(dir, "xbookmark")
      File.write(path_bin, "#!/bin/sh\n")
      File.chmod(0o755, path_bin)
      local = File.expand_path("../../../bin/xbookmark", __dir__)

      allow(File).to receive(:executable?).and_call_original
      allow(File).to receive(:executable?).with(local).and_return(false)
      allow(Gem).to receive(:bin_path).and_raise(Gem::Exception, "missing")
      stub_const("ENV", ENV.to_hash.merge("PATH" => dir))

      expect(scheduler.xbookmark_bin).to eq(path_bin)

      stub_const("ENV", ENV.to_hash.merge("PATH" => "/no/such/dir"))
      expect(scheduler.xbookmark_bin).to eq(local)
    end
  end
end
