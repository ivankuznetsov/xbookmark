# frozen_string_literal: true

require "thor"

module Xbookmark
  class CLI
    class Taxonomy < Thor
      def self.exit_on_failure?
        true
      end

      class_option :wiki, type: :string, desc: "Override the bookmark wiki path"
      class_option :vault, type: :string, desc: "Legacy alias for --wiki"
      class_option :verbose, type: :boolean, default: false, desc: "Verbose output"

      desc "audit", "Audit graph taxonomy health without modifying the wiki"
      def audit
        config, _store = load_runtime
        report = Xbookmark::Taxonomy::Auditor.new(vault_path: config.vault_path).call
        puts report
        exit(report.exit_code) unless report.exit_code.zero?
      end

      desc "rebuild", "Repair taxonomy paths and generated graph pages"
      option :apply, type: :boolean, default: false, desc: "Apply changes; dry-run by default"
      def rebuild
        config, store = load_runtime
        registrar = Xbookmark::Qmd::Registrar.new(config: config)
        report = Xbookmark::Taxonomy::Rebuilder.new(config: config, store: store, registrar: registrar).call(apply: options[:apply])
        puts report
        exit(report.exit_code) unless report.exit_code.zero?
      end

      private

      def load_runtime
        require_relative "../config"
        require_relative "../qmd/registrar"
        require_relative "../state/store"
        require_relative "../taxonomy/auditor"
        require_relative "../taxonomy/rebuilder"

        config = Xbookmark::Config.load(wiki_override: options[:wiki], vault_override: options[:vault], verbose: options[:verbose])
        [config, Xbookmark::State::Store.new(config.state_db_path)]
      end
    end
  end
end
