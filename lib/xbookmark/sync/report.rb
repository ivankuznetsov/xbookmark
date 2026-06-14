# frozen_string_literal: true

module Xbookmark
  module Sync
    class Report
      attr_accessor :synced, :skipped, :failed, :permanent_errors, :source_errors, :pages, :elapsed, :api_pages

      def initialize
        @synced = 0
        @skipped = 0
        @failed = 0
        @permanent_errors = 0
        @source_errors = 0
        @pages = 0
        @api_pages = 0
        @elapsed = 0.0
      end

      def to_s
        parts = ["synced #{synced}"]
        parts << "skipped #{skipped}" if skipped.positive?
        parts << "failed #{failed}, retrying next run" if failed.positive?
        parts << "permanent errors #{permanent_errors}" if permanent_errors.positive?
        parts << "source blocked #{source_errors}" if source_errors.positive?
        parts << "elapsed #{format("%.1f", elapsed)}s"
        parts << "api pages #{api_pages}" if api_pages.positive?
        parts.join(", ")
      end
    end
  end
end
