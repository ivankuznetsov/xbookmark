# frozen_string_literal: true

module Xbookmark
  module Sync
    class Report
      # Deliberately a loose accumulator: these counters are internal to the sync
      # subsystem (not a public API) and are incremented by hand by the Runner and
      # its collaborators as a run progresses. They are plain attr_accessor on
      # purpose — intent-named mutators would add ceremony for no behavior change.
      # The one field that guards an invariant (expired_source) is the exception
      # and is attr_reader-only with a dedicated mutator below.
      attr_accessor :synced, :skipped, :failed, :permanent_errors, :source_errors, :elapsed, :source_pages,
                    :bookmark_attempts, :partial, :maintenance_errors
      # expired_source is read-only from the outside: it can only be set through
      # #mark_session_expired, which records the browser source so session_expired?
      # can never be true with no source (the illegal state the derived predicate
      # exists to forbid).
      attr_reader :expired_source

      def initialize
        @synced = 0
        @skipped = 0
        @failed = 0
        @permanent_errors = 0
        @source_errors = 0
        # Pages pulled from any source (API or browser) — source-neutral so the
        # operator does not see "api pages" for pages the dev API never touched.
        @source_pages = 0
        @bookmark_attempts = 0
        @partial = 0
        @maintenance_errors = 0
        @elapsed = 0.0
        # nil = not expired. Set (via #mark_session_expired) to "browser" only
        # when the browser source raises Browser::SessionExpired on the sync /
        # retry / resync paths — the one source-block case that needs a human and
        # a notification. `session_expired?` derives from this single field so the
        # two can never disagree.
        @expired_source = nil
      end

      # Records that the browser session expired. Per plan U5 the browser is the
      # ONLY source that raises Browser::SessionExpired (the one source block
      # needing a human), so the culprit is the hardcoded "browser" rather than a
      # parameter — there is no second source that can ever set this, so a source
      # arg would be speculative (YAGNI). First-wins via ||= so a later block can't
      # change the culprit, and session_expired? derives from this single field.
      def mark_session_expired
        @expired_source ||= "browser"
      end

      def session_expired?
        !@expired_source.nil?
      end

      def to_s
        parts = ["synced #{synced}"]
        parts << "skipped #{skipped}" if skipped.positive?
        parts << "partial enrichment #{partial}" if partial.positive?
        parts << "failed #{failed}, retrying next run" if failed.positive?
        parts << "permanent errors #{permanent_errors}" if permanent_errors.positive?
        parts << "maintenance errors #{maintenance_errors}" if maintenance_errors.positive?
        parts << "source blocked #{source_errors}" if source_errors.positive?
        parts << "#{expired_source} session expired (re-login)" if session_expired?
        parts << "elapsed #{format("%.1f", elapsed)}s"
        parts << "source pages #{source_pages}" if source_pages.positive?
        parts.join(", ")
      end
    end
  end
end
