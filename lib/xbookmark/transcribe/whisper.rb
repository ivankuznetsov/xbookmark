# frozen_string_literal: true

require "open3"
require "fileutils"
require "shellwords"

module Xbookmark
  module Transcribe
    class Whisper
      CANDIDATE_BINS = %w[whisper-cli whisper-cpp whisper faster-whisper].freeze
      MIN_DURATION_MS = 1500
      DEFAULT_TIMEOUT = 300 # seconds — bound the whisper subprocess

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
        text = run_binary(bin, media_path)
        File.write(out_path, text)
        text
      end

      private

      def run_binary(bin, media_path)
        if @runner
          return @runner.call(bin, media_path, @model)
        end
        argv = build_argv(bin, media_path)
        out, err, status = run_with_timeout(argv, @timeout)
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
          out_reader = Thread.new { stdout.read }
          err_reader = Thread.new { stderr.read }

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
        when "whisper", "whisper-cpp"
          [bin, "--model", @model, "--output_format", "txt", "--output_dir", "-", media_path]
        else
          # whisper-cli (whisper.cpp): output to stdout via -nt -np
          [bin, "-m", @model, "-nt", "-np", "-f", media_path]
        end
      end
    end
  end
end
