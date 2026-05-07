# frozen_string_literal: true

require "thor"

module Xbookmark
  class CLI
    class Install < Thor::Group
      attr_reader :options

      def initialize(args = [], options = {}, _config = {})
        super
        @options = options
      end

      def run
        require_relative "../config"
        require_relative "../scheduler/factory"
        require_relative "../qmd/registrar"

        config = Xbookmark::Config.load(vault_override: options[:vault], verbose: options[:verbose])
        scheduler = Xbookmark::Scheduler::Factory.build(config: config)

        scheduler_options = {
          time: options[:time] || config.daily_sync_time,
          dry_run: options[:"dry-run"]
        }

        if options[:uninstall]
          scheduler.uninstall(**scheduler_options)
        else
          scheduler.install(**scheduler_options)
          unless options[:"dry-run"]
            registrar = Xbookmark::Qmd::Registrar.new(config: config)
            registrar.ensure_registered!
          end
        end
      end
    end
  end
end
