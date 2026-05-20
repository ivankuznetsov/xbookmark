# frozen_string_literal: true

require "thor"
require "fileutils"
require_relative "../paths"
require_relative "../keystore"
require_relative "../scheduler/installer"
require_relative "../config"

module Xbookmark
  class CLI
    class Uninstall < Thor::Group
      attr_reader :options

      def initialize(args = [], options = {}, _config = {})
        super
        @options   = options
        @input     = options[:input]  || $stdin
        @output    = options[:output] || $stdout
        @keystore  = options[:keystore] || Xbookmark::Keystore.default
        @scheduler = options[:scheduler]
      end

      # Returns 0 on success, non-zero if any step failed.  Each step is
      # idempotent and isolated — a failure in one does not block the
      # next; the exit code is the disjunction of all failures.
      def execute
        unless options[:purge]
          say "[xbookmark] pass --purge to remove the scheduler unit, keystore entries, and config directory."
          say "  refusing to run without --purge."
          return 1
        end

        unless options[:yes]
          return 1 unless confirm("Remove xbookmark scheduler unit, keystore entries, and #{Paths.default_config_dir}?")
        end

        failures = []

        say "[xbookmark] uninstalling scheduler unit…"
        begin
          installer.uninstall(dry_run: !!options[:"dry-run"])
        rescue StandardError => e
          say "  scheduler uninstall failed: #{e.message}"
          failures << :scheduler
        end

        say "[xbookmark] removing keystore entries…"
        begin
          removed = @keystore.delete_all
          if removed.empty?
            say "  no keystore entries to remove."
          else
            say "  removed: #{removed.join(", ")}"
          end
        rescue StandardError => e
          say "  keystore delete failed: #{e.message}"
          failures << :keystore
        end

        config_dir = Paths.default_config_dir
        if File.directory?(config_dir)
          say "[xbookmark] removing config directory #{config_dir}…"
          begin
            FileUtils.rm_rf(config_dir) unless !!options[:"dry-run"]
          rescue StandardError => e
            say "  config rm failed: #{e.message}"
            failures << :config
          end
        end

        if failures.empty?
          say "[xbookmark] uninstall complete."
          0
        else
          say "[xbookmark] uninstall finished with errors: #{failures.join(', ')}"
          1
        end
      end

      private

      def installer
        @scheduler ||= begin
          # Loading the config can raise when secrets have already been
          # cleared; fall through to a minimal stub config so uninstall
          # remains idempotent even on a partially-torn-down box.
          config =
            begin
              Xbookmark::Config.load
            rescue StandardError
              Struct::XbookmarkConfig.new(
                daily_sync_time: "06:00",
                logs_dir: Paths.default_logs_dir,
                env_file: nil
              )
            end
          Xbookmark::Scheduler::Installer.new(config: config)
        rescue Xbookmark::UnsupportedPlatform
          NoopInstaller.new
        end
      end

      def confirm(prompt)
        @output.print("#{prompt} [y/N] ")
        @output.flush if @output.respond_to?(:flush)
        answer = @input.gets.to_s.strip.downcase
        answer == "y" || answer == "yes"
      end

      def say(line)
        @output.puts(line)
      end

      class NoopInstaller
        def uninstall(*); end
      end
    end
  end
end
