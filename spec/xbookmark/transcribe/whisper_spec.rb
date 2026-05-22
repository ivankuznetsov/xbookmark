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

  it "resolves whisper.cpp model aliases near the configured binary" do
    Dir.mktmpdir do |dir|
      bin = File.join(dir, "whisper.cpp", "build", "bin", "whisper-cli")
      model = File.join(dir, "whisper.cpp", "models", "ggml-base.en.bin")
      audio = File.join(dir, "clip.wav")
      FileUtils.mkdir_p(File.dirname(bin))
      FileUtils.mkdir_p(File.dirname(model))
      File.write(bin, "")
      File.chmod(0o755, bin)
      File.write(model, "model")
      File.write(audio, "fake")

      observed_argv = nil
      status = instance_double(Process::Status, success?: true)
      whisper = described_class.new(binary: bin, model: "base.en")
      allow(whisper).to receive(:run_with_timeout) do |argv, _timeout|
        observed_argv = argv
        ["transcript", "", status]
      end

      expect(whisper.transcribe(audio, duration_ms: 5000)).to eq("transcript")
      expect(observed_argv).to include("-m", model)
    end
  end

  it "extracts video audio before passing it to whisper.cpp" do
    Dir.mktmpdir do |dir|
      bin = File.join(dir, "whisper.cpp", "build", "bin", "whisper-cli")
      model = File.join(dir, "whisper.cpp", "models", "ggml-base.en.bin")
      video = File.join(dir, "clip.mp4")
      FileUtils.mkdir_p(File.dirname(bin))
      FileUtils.mkdir_p(File.dirname(model))
      File.write(bin, "")
      File.chmod(0o755, bin)
      File.write(model, "model")
      File.write(video, "fake")

      status = instance_double(Process::Status, success?: true)
      observed_argv = nil
      observed_timeouts = []
      allow(described_class).to receive(:which).with("ffmpeg").and_return("/usr/bin/ffmpeg")
      whisper = described_class.new(binary: bin, model: "base.en")
      allow(whisper).to receive(:run_with_timeout) do |argv, timeout|
        observed_timeouts << timeout
        if argv.first == "/usr/bin/ffmpeg"
          File.write(argv.last, "wav")
          ["", "", status]
        else
          observed_argv = argv
          ["transcript", "", status]
        end
      end

      expect(whisper.transcribe(video, duration_ms: 1_000_000)).to eq("transcript")
      expect(observed_argv.last).to end_with(".wav")
      expect(observed_timeouts).to all(eq(3120))
    end
  end

  it "treats videos without audio streams as empty transcripts" do
    Dir.mktmpdir do |dir|
      bin = File.join(dir, "whisper.cpp", "build", "bin", "whisper-cli")
      model = File.join(dir, "whisper.cpp", "models", "ggml-base.en.bin")
      video = File.join(dir, "clip.mp4")
      FileUtils.mkdir_p(File.dirname(bin))
      FileUtils.mkdir_p(File.dirname(model))
      File.write(bin, "")
      File.chmod(0o755, bin)
      File.write(model, "model")
      File.write(video, "fake")

      status = instance_double(Process::Status, success?: false)
      allow(described_class).to receive(:which).with("ffmpeg").and_return("/usr/bin/ffmpeg")
      whisper = described_class.new(binary: bin, model: "base.en")
      allow(whisper).to receive(:run_with_timeout)
        .and_return(["", "Output file does not contain any stream", status])

      expect(whisper.transcribe(video, duration_ms: 5000)).to eq("")
    end
  end

  it "raises a setup error when a whisper.cpp model alias cannot be resolved" do
    Dir.mktmpdir do |dir|
      bin = File.join(dir, "whisper.cpp", "build", "bin", "whisper-cli")
      audio = File.join(dir, "clip.wav")
      FileUtils.mkdir_p(File.dirname(bin))
      File.write(bin, "")
      File.chmod(0o755, bin)
      File.write(audio, "fake")

      whisper = described_class.new(binary: bin, model: "base.en")

      expect { whisper.transcribe(audio, duration_ms: 5000) }
        .to raise_error(Xbookmark::WhisperUnavailable, /whisper\.cpp model not found/)
    end
  end

  it "detect returns nil when override does not exist and PATH has no candidate" do
    stub_const("ENV", ENV.to_hash.merge("PATH" => "/nonexistent"))
    expect(described_class.detect("/no/such/file")).to be_nil
    expect(described_class.detect).to be_nil
  end

  it "detects explicit PATH overrides, candidate binaries, and absolute executables" do
    Dir.mktmpdir do |dir|
      override = File.join(dir, "custom-whisper")
      candidate = File.join(dir, "whisper")
      File.write(override, "")
      File.write(candidate, "")
      File.chmod(0o755, override)
      File.chmod(0o755, candidate)
      stub_const("ENV", ENV.to_hash.merge("PATH" => dir))

      expect(described_class.detect("custom-whisper")).to eq("custom-whisper")
      expect(described_class.detect).to eq(candidate)
      expect(described_class.which(override)).to eq(override)
    end
  end

  it "raises when ffmpeg is unavailable or extraction fails for video input" do
    Dir.mktmpdir do |dir|
      bin = File.join(dir, "whisper")
      video = File.join(dir, "clip.mp4")
      File.write(bin, "")
      File.chmod(0o755, bin)
      File.write(video, "fake")

      allow(described_class).to receive(:which).with("ffmpeg").and_return(nil)
      whisper = described_class.new(binary: bin, model: "base.en")
      expect { whisper.transcribe(video, duration_ms: 5000) }
        .to raise_error(Xbookmark::WhisperUnavailable, /ffmpeg not found/)

      allow(described_class).to receive(:which).with("ffmpeg").and_return("/usr/bin/ffmpeg")
      status = instance_double(Process::Status, success?: false, exitstatus: 1)
      allow(whisper).to receive(:run_with_timeout).and_return(["", "codec exploded", status])
      expect { whisper.transcribe(video, duration_ms: 5000) }
        .to raise_error(Xbookmark::WhisperUnavailable, /audio extraction failed: codec exploded/)
    end
  end

  it "raises when the whisper subprocess fails" do
    Dir.mktmpdir do |dir|
      bin = File.join(dir, "whisper")
      audio = File.join(dir, "clip.wav")
      File.write(bin, "")
      File.chmod(0o755, bin)
      File.write(audio, "fake")
      status = instance_double(Process::Status, success?: false, exitstatus: 9)
      whisper = described_class.new(binary: bin, model: "base.en")
      allow(whisper).to receive(:run_with_timeout).and_return(["", "bad model", status])

      expect { whisper.transcribe(audio, duration_ms: 5000) }
        .to raise_error(Xbookmark::WhisperUnavailable, /whisper failed \(9\): bad model/)
    end
  end

  it "times out long-running subprocesses" do
    whisper = described_class.new(binary: RbConfig.ruby)

    out, err, status = whisper.send(:run_with_timeout, [RbConfig.ruby, "-e", "STDOUT.write 'ok'; STDERR.write 'warn'"], 2)
    expect([out, err, status.success?]).to eq(["ok", "warn", true])

    expect do
      whisper.send(:run_with_timeout, [RbConfig.ruby, "-e", "sleep 5"], 0.01)
    end.to raise_error(Xbookmark::WhisperUnavailable, /exceeded timeout/)
  end

  it "builds argv for every supported whisper backend and model form" do
    Dir.mktmpdir do |dir|
      explicit_model = File.join(dir, "model.bin")
      File.write(explicit_model, "model")
      faster = File.join(dir, "faster-whisper")
      openai = File.join(dir, "whisper")
      cpp = File.join(dir, "whisper-cpp")
      cli = File.join(dir, "whisper-cli")
      [faster, openai, cpp, cli].each { |path| File.write(path, ""); File.chmod(0o755, path) }

      whisper = described_class.new(binary: cli, model: explicit_model)
      expect(whisper.send(:build_argv, faster, "a.mp3")).to eq([faster, "--model", explicit_model, "--output", "-", "a.mp3"])
      expect(whisper.send(:build_argv, openai, "a.mp3")).to eq([openai, "--model", explicit_model, "--output_format", "txt", "--output_dir", "-", "a.mp3"])
      expect(whisper.send(:build_argv, cpp, "a.mp3")).to include(cpp, "--model", explicit_model, "--threads")
      expect(whisper.send(:build_argv, cli, "a.mp3")).to include(cli, "-m", explicit_model, "-nt", "-np", "-f", "a.mp3")
    end
  end

  it "honors WHISPER_THREADS when positive" do
    stub_const("ENV", ENV.to_hash.merge("WHISPER_THREADS" => "3"))
    whisper = described_class.new(binary: "/usr/bin/whisper-cli")

    expect(whisper.send(:whisper_threads)).to eq(3)
  end
end
