# frozen_string_literal: true

require "fileutils"
require "open3"
require "json"

module Xbookmark
  module Qmd
    class Registrar
      COLLECTION_NAME = "bookmarks"
      DEFAULT_TIMEOUT = 300

      def initialize(config:, runner: nil, timeout: DEFAULT_TIMEOUT)
        @config = config
        @runner = runner
        @timeout = timeout
      end

      def ensure_registered!
        return if registered?
        index! if register! == :needs_index
      end

      def registered?
        out, _err, status = capture(@config.qmd_bin, "collection", "list")
        out, _err, status = capture(@config.qmd_bin, "list") unless status_success?(status)
        return false unless status_success?(status)
        # Exact field match — substring matching let "old-bookmarks"
        # falsely report the canonical "bookmarks" collection as already
        # registered.
        out.lines.any? { |line| registered_line?(line) }
      rescue Errno::ENOENT
        false
      end

      def register!
        path = @config.vault_path
        FileUtils.mkdir_p(path)
        _out, err, status = capture(@config.qmd_bin, "collection", "add", path, "--name", COLLECTION_NAME)
        return :indexed if status_success?(status)

        _legacy_out, legacy_err, legacy_status = capture(@config.qmd_bin, "register", "--name", COLLECTION_NAME, "--path", path)
        return :needs_index if status_success?(legacy_status)

        err = [err, legacy_err].reject { |message| message.to_s.empty? }.join("\n")
        warn "[xbookmark] qmd register failed: #{err}"
        :failed
      end

      def index!
        _out, err, status = capture(@config.qmd_bin, "index", "--collection", COLLECTION_NAME)
        return if status_success?(status)

        _update_out, update_err, update_status = capture(@config.qmd_bin, "update")
        return if status_success?(update_status)

        err = [err, update_err].reject { |message| message.to_s.empty? }.join("\n")
        warn "[xbookmark] qmd index failed: #{err}"
      end

      private

      def capture(*argv)
        if @runner
          out, err, status = @runner.call(argv)
          [out, err, status]
        else
          capture_with_timeout(argv)
        end
      end

      def capture_with_timeout(argv)
        Open3.popen3(*argv) do |stdin, stdout, stderr, wait_thr|
          stdin.close
          out_reader = Thread.new { stdout.read rescue "" }
          err_reader = Thread.new { stderr.read rescue "" }

          if wait_thr.join(@timeout).nil?
            pid = wait_thr.pid
            Process.kill("TERM", pid) rescue nil
            50.times do
              break unless wait_thr.alive?
              sleep 0.1
            end
            Process.kill("KILL", pid) rescue nil if wait_thr.alive?
            wait_thr.join
            return ["", "qmd command timed out after #{@timeout}s: #{argv.join(' ')}", 1]
          end

          [out_reader.value, err_reader.value, wait_thr.value]
        end
      end

      def status_success?(status)
        status.respond_to?(:success?) ? status.success? : status == 0
      end

      def registered_line?(line)
        fields = line.split(/\s+/)
        return false unless fields.any? { |field| field == COLLECTION_NAME }

        legacy_path = File.join(@config.vault_path, "bookmarks")
        return false if fields.include?(legacy_path)

        true
      end
    end
  end
end
