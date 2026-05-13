# frozen_string_literal: true

require "xbookmark/transcribe/whisper"

RSpec.describe Xbookmark::Transcribe::Whisper do
  it "raises WhisperUnavailable when no binary is on PATH" do
    allow(described_class).to receive(:detect).and_return(nil)
    Dir.mktmpdir do |dir|
      audio = File.join(dir, "clip.wav")
      File.write(audio, "fake")
      whisper = described_class.new(binary: nil)
      expect { whisper.transcribe(audio, duration_ms: 5000) }
        .to raise_error(Xbookmark::WhisperUnavailable)
    end
  end

  it "skips short clips and returns empty string" do
    Dir.mktmpdir do |dir|
      audio = File.join(dir, "clip.wav")
      File.write(audio, "fake")
      whisper = described_class.new(binary: "/no/such/whisper-cli")
      expect(whisper.transcribe(audio, duration_ms: 500)).to eq("")
      expect(File.exist?("#{audio}.transcript.txt")).to be(false)
    end
  end

  it "writes a transcript file using a stub runner" do
    Dir.mktmpdir do |dir|
      audio = File.join(dir, "clip.wav")
      File.write(audio, "fake")
      whisper = described_class.new(binary: "/usr/bin/whisper-cli",
                                    runner: ->(bin, path, model) { "hello world model=#{model}" })
      result = whisper.transcribe(audio, duration_ms: 5000)
      expect(result).to include("hello world")
      expect(File.read("#{audio}.transcript.txt")).to include("hello world")
    end
  end

  it "detect returns nil when override does not exist and PATH has no candidate" do
    stub_const("ENV", ENV.to_hash.merge("PATH" => "/nonexistent"))
    expect(described_class.detect("/no/such/file")).to be_nil
  end
end
