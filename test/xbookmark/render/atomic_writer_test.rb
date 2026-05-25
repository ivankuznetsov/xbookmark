# frozen_string_literal: true

require "test_helper"

require "xbookmark/render/atomic_writer"

describe Xbookmark::Render::AtomicWriter do
  it "writes content atomically into a fresh path" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "deep", "nested", "file.md")
      described_class.write(path, "hello")
      assert_equal "hello", File.read(path)
      assert_empty Dir.glob(File.join(dir, "**/*.tmp.*"))
    end
  end

  it "leaves no .tmp behind when File.binwrite raises" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "x.md")
      File.stubs(:binwrite).raises(IOError, "boom")
      assert_raises(IOError) { described_class.write(path, "x") }
      assert_empty Dir.glob(File.join(dir, "*"))
    end
  end

  it "renames a directory atomically" do
    Dir.mktmpdir do |dir|
      src = File.join(dir, "scratch")
      dst = File.join(dir, "final")
      FileUtils.mkdir_p(src)
      File.write(File.join(src, "a.bin"), "ok")
      described_class.rename_dir(src, dst)
      assert_equal "ok", File.read(File.join(dst, "a.bin"))
      refute File.exist?(src)
    end
  end
end
