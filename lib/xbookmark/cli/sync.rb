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
        require_relative "../config"
        require_relative "../sync/runner"
        require_relative "../state/store"
        require_relative "../x/auth"
        require_relative "../x/client"

        config = Xbookmark::Config.load(vault_override: options[:vault], verbose: options[:verbose])
        store  = Xbookmark::State::Store.new(config.state_db_path)
        client = Xbookmark::X::Client.new(config: config, store: store)
        runner = Xbookmark::Sync::Runner.new(config: config, store: store, x_client: client)

        mode  = options[:limit] ? :backfill_limited : :backfill_full
        report = runner.run(mode: mode, limit: options[:limit])
        puts report.to_s
        exit_with(report)
      end

      def sync_run
        require_relative "../config"
        require_relative "../sync/runner"
        require_relative "../state/store"
        require_relative "../x/client"

        config = Xbookmark::Config.load(vault_override: options[:vault], verbose: options[:verbose])
        store  = Xbookmark::State::Store.new(config.state_db_path)
        client = Xbookmark::X::Client.new(config: config, store: store)
        runner = Xbookmark::Sync::Runner.new(config: config, store: store, x_client: client)

        report = runner.run(mode: :sync, from_scheduler: options[:"from-scheduler"])
        puts report.to_s
        exit_with(report)
      end

      def resync_run(tweet_id)
        require_relative "../config"
        require_relative "../sync/runner"
        require_relative "../state/store"
        require_relative "../x/client"

        config = Xbookmark::Config.load(vault_override: options[:vault], verbose: options[:verbose])
        store  = Xbookmark::State::Store.new(config.state_db_path)
        client = Xbookmark::X::Client.new(config: config, store: store)
        runner = Xbookmark::Sync::Runner.new(config: config, store: store, x_client: client)

        report = runner.run(mode: :resync, tweet_id: tweet_id)
        puts report.to_s
        exit_with(report)
      end

      private

      def exit_with(report)
        return if report.failed.zero? && report.permanent_errors.zero?
        # Permanent errors → user error (1); transient retry → transient (2).
        exit(report.permanent_errors.positive? ? 1 : 2)
      end
    end
  end
end
