# frozen_string_literal: true

require "test_helper"

require "xbookmark/transcribe/whisper"

describe Xbookmark::Transcribe::Whisper do
  it "raises WhisperUnavailable when no binary is on PATH" do
    described_class.stubs(:detect).returns(nil)
    Dir.mktmpdir do |dir|
      audio = File.join(dir, "clip.wav")
      File.write(audio, "fake")
      whisper = described_class.new(binary: nil)
      assert_raises(Xbookmark::WhisperUnavailable) { whisper.transcribe(audio, duration_ms: 5000) }
    end
  end

  it "skips short clips and returns empty string" do
    Dir.mktmpdir do |dir|
      audio = File.join(dir, "clip.wav")
      File.write(audio, "fake")
      whisper = described_class.new(binary: "/no/such/whisper-cli")
      assert_equal "", whisper.transcribe(audio, duration_ms: 500)
      refute File.exist?("#{audio}.transcript.txt")
    end
  end

  it "writes a transcript file using a stub runner" do
    Dir.mktmpdir do |dir|
      audio = File.join(dir, "clip.wav")
      File.write(audio, "fake")
      whisper = described_class.new(binary: "/usr/bin/whisper-cli",
                                    runner: ->(bin, path, model) { "hello world model=#{model}" })
      result = whisper.transcribe(audio, duration_ms: 5000)
      assert_includes result, "hello world"
      assert_includes File.read("#{audio}.transcript.txt"), "hello world"
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
      status = process_status(success: true)
      whisper = described_class.new(binary: bin, model: "base.en")
      whisper.define_singleton_method(:run_with_timeout) do |argv, _timeout|
        observed_argv = argv
        ["transcript", "", status]
      end

      assert_equal "transcript", whisper.transcribe(audio, duration_ms: 5000)
      assert_includes observed_argv, "-m"
      assert_includes observed_argv, model
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

      status = process_status(success: true)
      observed_argv = nil
      observed_timeouts = []
      described_class.stubs(:which).with("ffmpeg").returns("/usr/bin/ffmpeg")
      whisper = described_class.new(binary: bin, model: "base.en")
      whisper.define_singleton_method(:run_with_timeout) do |argv, timeout|
        observed_timeouts << timeout
        if argv.first == "/usr/bin/ffmpeg"
          File.write(argv.last, "wav")
          ["", "", status]
        else
          observed_argv = argv
          ["transcript", "", status]
        end
      end

      assert_equal "transcript", whisper.transcribe(video, duration_ms: 1_000_000)
      assert observed_argv.last.end_with?(".wav")
      assert observed_timeouts.all? { |timeout| timeout == 3120 }
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

      status = process_status(success: false)
      described_class.stubs(:which).with("ffmpeg").returns("/usr/bin/ffmpeg")
      whisper = described_class.new(binary: bin, model: "base.en")
      whisper.stubs(:run_with_timeout).returns(["", "Output file does not contain any stream", status])

      assert_equal "", whisper.transcribe(video, duration_ms: 5000)
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

      error = assert_raises(Xbookmark::WhisperUnavailable) { whisper.transcribe(audio, duration_ms: 5000) }
      assert_match(/whisper\.cpp model not found/, error.message)
    end
  end

  it "detect returns nil when override does not exist and PATH has no candidate" do
    with_env(ENV.to_h.merge("PATH" => "/nonexistent")) do
      assert_nil described_class.detect("/no/such/file")
      assert_nil described_class.detect
    end
  end

  it "detects explicit PATH overrides, candidate binaries, and absolute executables" do
    Dir.mktmpdir do |dir|
      override = File.join(dir, "custom-whisper")
      candidate = File.join(dir, "whisper")
      File.write(override, "")
      File.write(candidate, "")
      File.chmod(0o755, override)
      File.chmod(0o755, candidate)

      with_env(ENV.to_h.merge("PATH" => dir)) do
        assert_equal "custom-whisper", described_class.detect("custom-whisper")
        assert_equal candidate, described_class.detect
        assert_equal override, described_class.which(override)
      end
    end
  end

  it "raises when ffmpeg is unavailable or extraction fails for video input" do
    Dir.mktmpdir do |dir|
      bin = File.join(dir, "whisper")
      video = File.join(dir, "clip.mp4")
      File.write(bin, "")
      File.chmod(0o755, bin)
      File.write(video, "fake")

      described_class.stubs(:which).with("ffmpeg").returns(nil)
      whisper = described_class.new(binary: bin, model: "base.en")
      error = assert_raises(Xbookmark::WhisperUnavailable) { whisper.transcribe(video, duration_ms: 5000) }
      assert_match(/ffmpeg not found/, error.message)

      described_class.stubs(:which).with("ffmpeg").returns("/usr/bin/ffmpeg")
      status = process_status(success: false, exitstatus: 1)
      whisper.stubs(:run_with_timeout).returns(["", "codec exploded", status])
      error = assert_raises(Xbookmark::WhisperUnavailable) { whisper.transcribe(video, duration_ms: 5000) }
      assert_match(/audio extraction failed: codec exploded/, error.message)
    end
  end

  it "raises when the whisper subprocess fails" do
    Dir.mktmpdir do |dir|
      bin = File.join(dir, "whisper")
      audio = File.join(dir, "clip.wav")
      File.write(bin, "")
      File.chmod(0o755, bin)
      File.write(audio, "fake")
      status = process_status(success: false, exitstatus: 9)
      whisper = described_class.new(binary: bin, model: "base.en")
      whisper.stubs(:run_with_timeout).returns(["", "bad model", status])

      error = assert_raises(Xbookmark::WhisperUnavailable) { whisper.transcribe(audio, duration_ms: 5000) }
      assert_match(/whisper failed \(9\): bad model/, error.message)
    end
  end

  it "times out long-running subprocesses" do
    whisper = described_class.new(binary: RbConfig.ruby)

    out, err, status = whisper.send(:run_with_timeout, [RbConfig.ruby, "-e", "STDOUT.write 'ok'; STDERR.write 'warn'"], 2)
    assert_equal ["ok", "warn", true], [out, err, status.success?]

    error = assert_raises(Xbookmark::WhisperUnavailable) do
      whisper.send(:run_with_timeout, [RbConfig.ruby, "-e", "sleep 5"], 0.01)
    end
    assert_match(/exceeded timeout/, error.message)
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
      assert_equal [faster, "--model", explicit_model, "--output", "-", "a.mp3"], whisper.send(:build_argv, faster, "a.mp3")
      assert_equal [openai, "--model", explicit_model, "--output_format", "txt", "--output_dir", "-", "a.mp3"], whisper.send(:build_argv, openai, "a.mp3")
      assert_includes whisper.send(:build_argv, cpp, "a.mp3"), cpp
      assert_includes whisper.send(:build_argv, cpp, "a.mp3"), "--model"
      assert_includes whisper.send(:build_argv, cpp, "a.mp3"), explicit_model
      assert_includes whisper.send(:build_argv, cpp, "a.mp3"), "--threads"
      assert_includes whisper.send(:build_argv, cli, "a.mp3"), cli
      assert_includes whisper.send(:build_argv, cli, "a.mp3"), "-m"
      assert_includes whisper.send(:build_argv, cli, "a.mp3"), explicit_model
      assert_includes whisper.send(:build_argv, cli, "a.mp3"), "-nt"
      assert_includes whisper.send(:build_argv, cli, "a.mp3"), "-np"
      assert_includes whisper.send(:build_argv, cli, "a.mp3"), "-f"
      assert_includes whisper.send(:build_argv, cli, "a.mp3"), "a.mp3"
    end
  end

  it "honors WHISPER_THREADS when positive" do
    with_env(ENV.to_h.merge("WHISPER_THREADS" => "3")) do
      whisper = described_class.new(binary: "/usr/bin/whisper-cli")

      assert_equal 3, whisper.send(:whisper_threads)
    end
  end
end
