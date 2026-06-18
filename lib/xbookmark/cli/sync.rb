# frozen_string_literal: true

require "thor"

module Xbookmark
  class CLI
    class Sync < Thor::Group
      include Thor::Actions

      attr_reader :options

      def initialize(args = [], options = {}, _config = {})
        super
        @options = options
      end

      def backfill_run
        runner = build_runner
        mode  = options[:limit] ? :backfill_limited : :backfill_full
        report = runner.run(mode: mode, limit: options[:limit])
        puts report
        exit_with(report)
      end

      def sync_run
        runner = build_runner
        report = runner.run(mode: :sync, from_scheduler: options[:"from-scheduler"])
        puts report
        exit_with(report)
      end

      def resync_run(tweet_id)
        runner = build_runner
        report = runner.run(mode: :resync, tweet_id: tweet_id)
        puts report
        exit_with(report)
      end

      # Offline: re-runs the current enrichment contract over notes already in
      # the wiki (no X fetch). Reads config without X auth.
      def reenrich_run
        require_relative "../config"
        require_relative "../sync/reenricher"
        require_relative "../state/store"

        config = Xbookmark::Config.load_offline(wiki_override: options[:wiki], vault_override: options[:vault], verbose: options[:verbose])
        store  = Xbookmark::State::Store.new(config.state_db_path)

        report = Xbookmark::Sync::Reenricher.new(config: config, store: store, model: options[:model],
                                                 reasoning_effort: options[:"reasoning-effort"]).call(limit: options[:limit])
        exit(report.exit_code) unless report.exit_code.zero?
      end

      private

      # Shared wiring for the fetch commands (backfill/sync/resync): load config,
      # open the store, build the sources, and assemble the Runner. Kept in one
      # place so a future dependency change (a new source, a different store) is a
      # single edit rather than three parallel ones.
      def build_runner
        require_relative "../config"
        require_relative "../sync/runner"
        require_relative "../state/store"
        require_relative "../x/auth"
        require_relative "../sources/factory"

        config = Xbookmark::Config.load(wiki_override: options[:wiki], vault_override: options[:vault], verbose: options[:verbose])
        store  = Xbookmark::State::Store.new(config.state_db_path)
        sources = Xbookmark::Sources::Factory.build(config: config, store: store)
        Xbookmark::Sync::Runner.new(config: config, store: store, sources: sources)
      end

      def exit_with(report)
        # Browser session expiry is the one source-block case that is
        # intentionally noisy: notify a human and exit non-zero even under
        # --from-scheduler, distinct from the API-token-block degrade-to-0 path.
        if report.session_expired?
          notify_session_expired(report)
          exit 1
        end

        maintenance_errors = report.maintenance_errors
        return if report.failed.zero? && report.permanent_errors.zero? && report.source_errors.zero? && maintenance_errors.zero?
        # An unattended scheduled run is best-effort: tolerate retryable trouble
        # (X source outages AND transient enrichment failures, both of which
        # auto-retry next run) so the timer doesn't report "failed" for things
        # that heal themselves. Only genuine dead-ends — permanent errors and
        # destructive maintenance failures — fail a scheduled run.
        return if options[:"from-scheduler"] && report.permanent_errors.zero? && maintenance_errors.zero?

        # Permanent errors → user error (1); transient retry → transient (2).
        exit(report.permanent_errors.positive? || report.source_errors.positive? || maintenance_errors.positive? ? 1 : 2)
      end

      def notify_session_expired(report)
        require_relative "../notify"
        source = report.expired_source
        # Stable, grep-able stderr token so a wrapper can tell "needs re-login"
        # apart from a generic exit 1 without scraping prose. Documented next to
        # the 0/1/2 exit contract in the README Scheduling section.
        warn "[xbookmark] SESSION_EXPIRED source=#{source}; re-run `xbookmark auth login --browser` to restore sync."
        Xbookmark::Notify.deliver(
          "xbookmark: #{source} session expired",
          "Re-run `xbookmark auth login --browser` to restore bookmark sync."
        )
      end
    end
  end
end
