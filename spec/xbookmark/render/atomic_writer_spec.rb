# frozen_string_literal: true

require "xbookmark/render/atomic_writer"

RSpec.describe Xbookmark::Render::AtomicWriter do
  it "writes content atomically into a fresh path" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "deep", "nested", "file.md")
      described_class.write(path, "hello")
      expect(File.read(path)).to eq("hello")
      expect(Dir.glob(File.join(dir, "**/*.tmp.*"))).to be_empty
    end
  end

  it "leaves no .tmp behind when File.binwrite raises" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "x.md")
      allow(File).to receive(:binwrite).and_raise(IOError, "boom")
      expect { described_class.write(path, "x") }.to raise_error(IOError)
      expect(Dir.glob(File.join(dir, "*"))).to be_empty
    end
  end

  it "renames a directory atomically" do
    Dir.mktmpdir do |dir|
      src = File.join(dir, "scratch")
      dst = File.join(dir, "final")
      FileUtils.mkdir_p(src)
      File.write(File.join(src, "a.bin"), "ok")
      described_class.rename_dir(src, dst)
      expect(File.read(File.join(dst, "a.bin"))).to eq("ok")
      expect(File.exist?(src)).to be(false)
    end
  end
end
