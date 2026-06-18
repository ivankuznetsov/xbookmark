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

        config = Xbookmark::Config.load(wiki_override: options[:wiki], vault_override: options[:vault], verbose: options[:verbose])

        platform = Paths.macos? ? "macOS" : (Paths.linux? ? "Linux" : "unknown")
        say "platform: #{platform}"
        say "scheduler backend: #{platform == "macOS" ? "launchd" : "systemd"}"
        say "ruby: #{Xbookmark::System::Runtime.describe}"
        say "keystore: #{safe_keystore_backend}"
        say "bookmark wiki: #{config.vault_path}"
        say "state db: #{config.state_db_path}"

        missing = []
        missing << "codex"   unless check_bin("codex",   config.codex_bin)
        missing << "whisper" unless whisper_ok?(config)
        missing << "qmd"     unless check_bin("qmd",     config.qmd_bin)
        missing << "ffmpeg"  unless check_bin("ffmpeg",  "ffmpeg")

        report_x_auth(config)

        report_browser(config, missing)

        if missing.any?
          render_fixes(missing)
        end

        # `doctor` is a diagnostic — never fail just because an external tool
        # is missing; the install one-liners above are the actionable output.
        0
      end

      private

      # In browser-only mode no X API token is expected, so don't nag the user to
      # run the dev-API OAuth login they deliberately opted out of.
      def report_x_auth(config)
        source = Xbookmark::Config.source_of(config)
        unless Xbookmark::Config.api_source?(source)
          say "X auth: not required (source=#{source})"
          return
        end

        if config.x_access_token.to_s.empty?
          say "X auth: NOT logged in (run: xbookmark auth login)"
        else
          say "X auth: token present (expires_at=#{config.x_token_expires_at || "unknown"})"
        end
      end

      # Browser bookmark source readiness. Chromium is required-but-not-bundled,
      # so this is the runtime check that it is present; nothing here launches a
      # browser. The session's true validity is verified on the next sync.
      def report_browser(config, missing)
        require_relative "../browser/chromium"
        require_relative "../browser/session"

        source = Xbookmark::Config.source_of(config)
        say ""
        say "source: #{source}"

        chromium = Xbookmark::Browser::Chromium.detect
        if chromium
          say "chromium: ok (#{chromium})"
        else
          say "chromium: NOT FOUND (the browser source needs a system Chromium; e.g. install chromium/google-chrome)"
          # Chromium is the browser source's one mandatory binary, so feed it into
          # the same `missing` list (and `--fix` install one-liners) as the other
          # tools — but only when the browser source is active, so an API-only host
          # is not told to install a browser it never uses.
          missing << "chromium" if Xbookmark::Config.browser_source?(source)
        end

        profile = Xbookmark::Paths.browser_profile_dir
        say "browser profile: #{profile}"

        # Only report (and re-harden) the saved session when the browser source is
        # active — mirrors report_x_auth's api_source? gate, so an api-only host's
        # health check grepping "browser session:" does not see a perpetual
        # not-set-up line for a source it deliberately opted out of.
        return unless Xbookmark::Config.browser_source?(source)

        saved, message = Xbookmark::Browser::Session.describe_profile(profile)
        say "browser session: #{message}"
        return if saved

        # Stable, grep-able stderr token (parity with `auth status`'s
        # BROWSER_SESSION_MISSING) so an agent grepping doctor stderr for
        # `[xbookmark]` tokens sees the not-set-up session rather than concluding
        # readiness from a clean exit while stdout says "browser session: not set up".
        warn "[xbookmark] BROWSER_SESSION_MISSING source=#{source}; re-run `xbookmark auth login --browser`."
      end

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
        path = Xbookmark::Paths.which(bin)
        if path
          say "#{label}: ok (#{path})"
          true
        else
          say "#{label}: NOT FOUND in PATH (#{bin})"
          false
        end
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

        # `--fix` prompts on @input.gets; never block on a non-interactive stdin
        # (an unattended agent/scheduler shell) — the commands above are already
        # printed, so just point the operator at them. Mirrors Login/Setup.
        unless tty_input?
          # Grep-able stderr token (parity with the other CLI tokens) so an agent
          # can branch on the non-interactive bail rather than parsing the prose.
          warn "[xbookmark] DOCTOR_FIX_NONINTERACTIVE; doctor --fix needs an interactive terminal; run the printed install commands manually."
          say ""
          say "doctor --fix needs an interactive terminal to confirm; run the commands above manually instead."
          return
        end

        commands.each do |(tool, cmd)|
          next if cmd.nil?
          say ""
          say "Run `#{cmd.join(' ')}`? [y/N]"
          answer = @input.gets.to_s.strip.downcase
          if %w[y yes].include?(answer)
            system(*cmd)
          else
            say "  skipped #{tool}"
          end
        end
      end

      def tty_input?
        @input.respond_to?(:tty?) && @input.tty?
      end

      def say(line)
        @output.puts(line)
      end
    end
  end
end
