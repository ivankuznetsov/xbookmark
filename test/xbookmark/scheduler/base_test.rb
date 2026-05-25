# frozen_string_literal: true

require "test_helper"

require "xbookmark/scheduler/base"

describe Xbookmark::Scheduler::Base do
  let(:scheduler) { described_class.new(config: Object.new) }

  it "requires concrete scheduler subclasses to implement public actions" do
    assert_raises(NotImplementedError) { scheduler.install(time: "06:00") }
    assert_raises(NotImplementedError) { scheduler.uninstall }
    assert_raises(NotImplementedError) { scheduler.status }
  end

  it "parses valid scheduler times and rejects malformed times" do
    assert_equal [3, 5], scheduler.send(:parse_time, "03:05")
    error = assert_raises(Xbookmark::Error) { scheduler.send(:parse_time, "3:5") }
    assert_match(/invalid time/, error.message)
  end

  it "prefers the local checkout executable" do
    assert scheduler.xbookmark_bin.end_with?("/bin/xbookmark")
  end

  it "falls back to an installed gem executable when the checkout executable is absent" do
    Dir.mktmpdir do |dir|
      gem_bin = File.join(dir, "xbookmark")
      File.write(gem_bin, "#!/bin/sh\n")
      File.chmod(0o755, gem_bin)
      local = File.expand_path("../../../bin/xbookmark", __dir__)

      File.stubs(:executable?).with(local).returns(false)
      File.stubs(:executable?).with(gem_bin).returns(true)
      Gem.stubs(:bin_path).with("xbookmark", "xbookmark").returns(gem_bin)

      assert_equal gem_bin, scheduler.xbookmark_bin
    end
  end

  it "falls back to PATH and then the local path when no executable can be found" do
    Dir.mktmpdir do |dir|
      path_bin = File.join(dir, "xbookmark")
      File.write(path_bin, "#!/bin/sh\n")
      File.chmod(0o755, path_bin)
      local = File.expand_path("../../../bin/xbookmark", __dir__)

      File.stubs(:executable?).returns(false)
      File.stubs(:executable?).with(path_bin).returns(true)
      Gem.stubs(:bin_path).raises(Gem::Exception, "missing")
      ENV["PATH"] = dir

      assert_equal path_bin, scheduler.xbookmark_bin

      ENV["PATH"] = "/no/such/dir"
      assert_equal local, scheduler.xbookmark_bin
    end
  end
end
