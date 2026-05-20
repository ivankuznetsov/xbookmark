# frozen_string_literal: true

require "thor"

module Xbookmark
  class CLI
    class Doctor < Thor::Group
      attr_reader :options

      def initialize(args = [], options = {}, _config = {})
        super
        @options = options
        @input  = options[:input]  || $stdin
        @output = options[:output] || $stdout
      end

      def execute
        require_relative "../config"
        require_relative "../paths"
        require_relative "../enrich/codex"
        require_relative "../transcribe/whisper"
        require_relative "../keystore"
        require_relative "../system/runtime"
        require_relative "../system/package_manager"

        config = Xbookmark::Config.load(vault_override: options[:vault], verbose: options[:verbose])

        platform = Paths.macos? ? "macOS" : (Paths.linux? ? "Linux" : "unknown")
        say "platform: #{platform}"
        say "scheduler backend: #{platform == "macOS" ? "launchd" : "systemd"}"
        say "ruby: #{Xbookmark::System::Runtime.describe}"
        say "keystore: #{safe_keystore_backend}"
        say "vault: #{config.vault_path}"
        say "state db: #{config.state_db_path}"

        missing = []
        missing << "codex"   unless check_bin("codex",   config.codex_bin)
        unless whisper_ok?(config)
          missing << "whisper"
        end
        missing << "qmd"     unless check_bin("qmd",     config.qmd_bin)
        missing << "ffmpeg"  unless check_bin("ffmpeg",  "ffmpeg")

        if config.x_access_token.to_s.empty?
          say "X auth: NOT logged in (run: xbookmark auth login)"
        else
          say "X auth: token present (expires_at=#{config.x_token_expires_at || "unknown"})"
        end

        if missing.any?
          render_fixes(missing)
        end

        # `doctor` is a diagnostic — never fail just because an external tool
        # is missing; the install one-liners above are the actionable output.
        0
      end

      private

      def safe_keystore_backend
        Xbookmark::Keystore.default.backend_name
      rescue StandardError => e
        "unavailable (#{e.class})"
      end

      def whisper_ok?(config)
        whisper = Xbookmark::Transcribe::Whisper.detect(config.whisper_bin)
        if whisper
          say "whisper: ok (#{whisper})"
          true
        else
          say "whisper: NOT FOUND (install whisper.cpp via your package manager)"
          false
        end
      end

      def check_bin(label, bin)
        path = which(bin)
        if path
          say "#{label}: ok (#{path})"
          true
        else
          say "#{label}: NOT FOUND in PATH (#{bin})"
          false
        end
      end

      def which(cmd)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
          full = File.join(dir, cmd)
          return full if File.executable?(full) && !File.directory?(full)
        end
        nil
      end

      def render_fixes(missing)
        manager = Xbookmark::System::PackageManager.detect
        say ""
        say "Missing tools: #{missing.join(", ")}"
        if manager == :unknown
          say "  (no supported package manager detected; install manually)"
          return
        end

        commands = missing.map do |tool|
          [tool, Xbookmark::System::PackageManager.install_command(tool, manager: manager)]
        end

        commands.each do |(tool, cmd)|
          if cmd.nil?
            say "  #{tool}: install manually (no package known for #{manager})"
          else
            say "  #{tool}: #{cmd.join(' ')}"
          end
        end

        return unless options[:fix]

        commands.each do |(tool, cmd)|
          next if cmd.nil?
          say ""
          say "Run `#{cmd.join(' ')}`? [y/N]"
          answer = @input.gets.to_s.strip.downcase
          if answer == "y" || answer == "yes"
            system(*cmd)
          else
            say "  skipped #{tool}"
          end
        end
      end

      def say(line)
        @output.puts(line)
      end
    end
  end
end
