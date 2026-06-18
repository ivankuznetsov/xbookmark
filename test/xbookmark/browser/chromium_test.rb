# frozen_string_literal: true

require "test_helper"
require "xbookmark/browser/chromium"

describe Xbookmark::Browser::Chromium do
  it "returns the first Chromium-family binary found on PATH" do
    Dir.mktmpdir do |dir|
      bin = File.join(dir, "chromium")
      File.write(bin, "#!/bin/sh\n")
      File.chmod(0o755, bin)
      ENV["PATH"] = dir

      assert_equal bin, described_class.detect
    end
  end

  it "finds google-chrome-stable when chromium is absent" do
    Dir.mktmpdir do |dir|
      bin = File.join(dir, "google-chrome-stable")
      File.write(bin, "#!/bin/sh\n")
      File.chmod(0o755, bin)
      ENV["PATH"] = dir

      assert_equal bin, described_class.detect
    end
  end

  it "returns nil when no Chromium is installed" do
    Dir.mktmpdir do |dir|
      ENV["PATH"] = dir
      # No PATH binary and no macOS app present.
      File.stubs(:executable?).returns(false)

      assert_nil described_class.detect
    end
  end

  it "falls back to the macOS /Applications path when PATH has none" do
    Dir.mktmpdir do |dir|
      ENV["PATH"] = dir
      app = Xbookmark::Browser::Chromium::MACOS_APP_PATHS.first
      File.stubs(:executable?).returns(false)
      File.stubs(:directory?).returns(false)
      File.stubs(:executable?).with(app).returns(true)

      assert_equal app, described_class.detect
    end
  end

  it "ignores a PATH entry that is a directory, not an executable file" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "chromium"))
      ENV["PATH"] = dir

      assert_nil described_class.which("chromium")
    end
  end
end
