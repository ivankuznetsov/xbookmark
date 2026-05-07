# frozen_string_literal: true

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
        register!
        index!
      end

      def registered?
        out, _err, status = capture(@config.qmd_bin, "list")
        return false unless status_success?(status)
        out.lines.any? { |l| l.include?(COLLECTION_NAME) }
      rescue Errno::ENOENT
        false
      end

      def register!
        path = File.join(@config.vault_path, "bookmarks")
        FileUtils.mkdir_p(path)
        _out, err, status = capture(@config.qmd_bin, "register", "--name", COLLECTION_NAME, "--path", path)
        unless status_success?(status)
          warn "[xbookmark] qmd register failed: #{err}"
        end
      end

      def index!
        _out, err, status = capture(@config.qmd_bin, "index", "--collection", COLLECTION_NAME)
        unless status_success?(status)
          warn "[xbookmark] qmd index failed: #{err}"
        end
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
