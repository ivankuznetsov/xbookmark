# frozen_string_literal: true

require_relative "factory"

module Xbookmark
  module Scheduler
    # Thin wrapper around the platform-specific scheduler.  Exposes the
    # same surface to both the wizard and the existing `xbookmark
    # install` CLI command so they share one code path.
    class Installer
      def initialize(config:, scheduler: nil)
        @config = config
        @scheduler = scheduler || Factory.build(config: config)
      end

      def install(time: nil, dry_run: false)
        @scheduler.install(time: time || @config.daily_sync_time, dry_run: dry_run)
      end

      def uninstall(time: nil, dry_run: false)
        @scheduler.uninstall(time: time, dry_run: dry_run)
      end

      def status
        @scheduler.status
      end
    end
  end
end
