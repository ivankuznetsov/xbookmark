# frozen_string_literal: true

require "open3"
require "fileutils"
require "etc"
require "shellwords"
require "tmpdir"

require_relative "../../xbookmark"

module Xbookmark
  module Transcribe
    class Whisper
      CANDIDATE_BINS = %w[whisper-cli whisper-cpp whisper faster-whisper].freeze
      MIN_DURATION_MS = 1500
      DEFAULT_TIMEOUT = 300 # seconds — bound the whisper subprocess
      TIMEOUT_SECONDS_PER_AUDIO_SECOND = 3
      TIMEOUT_PADDING_SECONDS = 120
      DEFAULT_THREADS = [[Etc.nprocessors, 8].min, 1].max

      class << self
        # Probes the configured / PATH for a known whisper binary.
        # Accepts an explicit override.
        def detect(override = nil)
          if override && !override.to_s.empty?
            return override if File.executable?(override) || which(override)
            return nil
          end
          CANDIDATE_BINS.each do |c|
            path = which(c)
            return path if path
          end
          nil
        end

        def which(cmd)
          return cmd if File.absolute_path?(cmd) && File.executable?(cmd)
          ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
            full = File.join(dir, cmd)
            return full if File.executable?(full) && !File.directory?(full)
          end
          nil
        end
      end

      def initialize(binary: nil, model: "base.en", runner: nil, timeout: DEFAULT_TIMEOUT)
        @binary = binary
        @model = model
        @runner = runner # injectable for tests
        @timeout = timeout
      end

      # Returns transcript text. Writes <media_path>.transcript.txt next to media.
      def transcribe(media_path, duration_ms: nil)
        return "" if duration_ms && duration_ms < MIN_DURATION_MS
        bin = @binary || self.class.detect
        raise Xbookmark::WhisperUnavailable, "no whisper binary found in PATH" unless bin

        out_path = "#{media_path}.transcript.txt"
        text = transcribe_input(bin, media_path, duration_ms: duration_ms)
        File.write(out_path, text)
        text
      end

      private

      def transcribe_input(bin, media_path, duration_ms:)
        timeout = timeout_for(duration_ms)
        return run_binary(bin, media_path) if @runner
        return run_binary(bin, media_path, timeout: timeout) if wav_file?(media_path)

        with_extracted_audio(media_path, timeout: timeout) do |audio_path|
          run_binary(bin, audio_path, timeout: timeout)
        end
      end

      def timeout_for(duration_ms)
        return @timeout unless duration_ms

        seconds = duration_ms.to_f / 1000
        [@timeout, (seconds * TIMEOUT_SECONDS_PER_AUDIO_SECOND).ceil + TIMEOUT_PADDING_SECONDS].max
      end

      def wav_file?(media_path)
        %w[.wav .wave].include?(File.extname(media_path).downcase)
      end

      def with_extracted_audio(media_path, timeout:)
        ffmpeg = self.class.which("ffmpeg")
        raise Xbookmark::WhisperUnavailable, "ffmpeg not found in PATH" unless ffmpeg

        Dir.mktmpdir("xbookmark-whisper-") do |dir|
          audio_path = File.join(dir, "#{File.basename(media_path, ".*")}.wav")
          out, err, status = run_with_timeout(
            [ffmpeg, "-y", "-v", "error", "-i", media_path, "-vn", "-ac", "1", "-ar", "16000", "-f", "wav", audio_path],
            timeout
          )

          unless status.success? && File.size?(audio_path)
            message = err.to_s.strip.empty? ? out.to_s.strip : err.to_s.strip
            return "" if no_audio_stream?(message)

            raise Xbookmark::WhisperUnavailable, "ffmpeg audio extraction failed: #{message}"
          end

          yield audio_path
        end
      end

      def no_audio_stream?(message)
        message.match?(/does not contain any stream|matches no streams|no audio streams?/i)
      end

      def run_binary(bin, media_path, timeout: @timeout)
        if @runner
          return @runner.call(bin, media_path, @model)
        end
        argv = build_argv(bin, media_path)
        out, err, status = run_with_timeout(argv, timeout)
        unless status.success?
          # Whisper failures belong in the WhisperUnavailable taxonomy —
          # the previous CodexError tag misled logs into blaming the LLM
          # subsystem for a transcription crash.
          raise Xbookmark::WhisperUnavailable, "whisper failed (#{status.exitstatus}): #{err}"
        end
        out
      end

      def run_with_timeout(argv, timeout)
        Open3.popen3(*argv) do |stdin, stdout, stderr, wait_thr|
          stdin.close
          out_reader = Thread.new { stdout.read rescue "" }
          err_reader = Thread.new { stderr.read rescue "" }

          if wait_thr.join(timeout).nil?
            pid = wait_thr.pid
            Process.kill("TERM", pid) rescue nil
            50.times do
              break unless wait_thr.alive?
              sleep 0.1
            end
            Process.kill("KILL", pid) rescue nil if wait_thr.alive?
            wait_thr.join
            raise Xbookmark::WhisperUnavailable, "whisper exceeded timeout of #{timeout}s"
          end

          [out_reader.value, err_reader.value, wait_thr.value]
        end
      end

      def build_argv(bin, media_path)
        case File.basename(bin)
        when "faster-whisper"
          [bin, "--model", @model, "--output", "-", media_path]
        when "whisper-cpp"
          [bin, "--model", whisper_cpp_model(bin), "--threads", whisper_threads.to_s,
           "--output_format", "txt", "--output_dir", "-", media_path]
        when "whisper"
          [bin, "--model", @model, "--output_format", "txt", "--output_dir", "-", media_path]
        else
          # whisper-cli (whisper.cpp): output to stdout via -nt -np
          [bin, "-m", whisper_cpp_model(bin), "-t", whisper_threads.to_s, "-nt", "-np", "-f", media_path]
        end
      end

      def whisper_threads
        configured = ENV["WHISPER_THREADS"].to_i
        configured.positive? ? configured : DEFAULT_THREADS
      end

      def whisper_cpp_model(bin)
        explicit = expanded_existing_model(@model)
        return explicit if explicit

        filename = @model.to_s.start_with?("ggml-") ? @model.to_s : "ggml-#{@model}.bin"
        candidates = whisper_cpp_model_dirs(bin).map { |dir| File.expand_path(File.join(dir, filename)) }
        found = candidates.find { |path| File.file?(path) }
        return found if found

        raise Xbookmark::WhisperUnavailable,
              "whisper.cpp model not found for WHISPER_MODEL=#{@model.inspect}; expected one of: #{candidates.join(", ")}"
      end

      def expanded_existing_model(model)
        return nil if model.to_s.strip.empty?
        path = File.expand_path(model.to_s)
        File.file?(path) ? path : nil
      end

      def whisper_cpp_model_dirs(bin)
        [
          ENV["WHISPER_MODEL_DIR"],
          File.join(File.dirname(bin), "..", "..", "models"),
          File.join(File.dirname(bin), "..", "models"),
          File.join(Dir.pwd, "models")
        ].compact
      end
    end
  end
end
