# frozen_string_literal: true

require "thor"

module Xbookmark
  class CLI
    class Doctor < Thor::Group
      attr_reader :options

      def initialize(args = [], options = {}, _config = {})
        super
        @options = options
      end

      def execute
        require_relative "../config"
        require_relative "../paths"
        require_relative "../enrich/codex"
        require_relative "../transcribe/whisper"

        config = Xbookmark::Config.load(vault_override: options[:vault], verbose: options[:verbose])

        platform = Paths.macos? ? "macOS" : (Paths.linux? ? "Linux" : "unknown")
        puts "platform: #{platform}"
        puts "scheduler backend: #{platform == "macOS" ? "launchd" : "systemd"}"
        puts "vault: #{config.vault_path}"
        puts "state db: #{config.state_db_path}"

        check_bin("codex", config.codex_bin)
        whisper = Xbookmark::Transcribe::Whisper.detect(config.whisper_bin)
        if whisper
          puts "whisper: ok (#{whisper})"
        else
          puts "whisper: NOT FOUND (install whisper.cpp via your package manager)"
        end
        check_bin("qmd", config.qmd_bin)

        if config.x_access_token.to_s.empty?
          puts "X auth: NOT logged in (run: xbookmark auth login)"
        else
          puts "X auth: token present (expires_at=#{config.x_token_expires_at || "unknown"})"
        end
      end

      private

      def check_bin(label, bin)
        path = which(bin)
        if path
          puts "#{label}: ok (#{path})"
        else
          puts "#{label}: NOT FOUND in PATH (#{bin})"
        end
      end

      def which(cmd)
        # PATHEXT is Windows-only; xbookmark only ships scheduler
        # integration for Linux (systemd) and macOS (launchd), so the
        # extension loop is dead weight that triggered one false-positive
        # `cmd` lookup per PATH entry.
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
          full = File.join(dir, cmd)
          return full if File.executable?(full) && !File.directory?(full)
        end
        nil
      end
    end
  end
end
