# frozen_string_literal: true

require "fileutils"
require "open3"
require "json"

module Xbookmark
  module Qmd
    class Registrar
      COLLECTION_NAME = "bookmarks"

      def initialize(config:, runner: nil)
        @config = config
        @runner = runner
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
        out.lines.any? do |line|
          line.split(/\s+/).any? { |field| field == COLLECTION_NAME }
        end
      rescue Errno::ENOENT
        false
      end

      def register!
        path = File.join(@config.vault_path, "bookmarks")
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
          Open3.capture3(*argv)
        end
      end

      def status_success?(status)
        status.respond_to?(:success?) ? status.success? : status == 0
      end
    end
  end
end
