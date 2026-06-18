# frozen_string_literal: true

require "thor"
require "time"

module Xbookmark
  class CLI
    class Auth < Thor
      class_option :wiki, type: :string
      class_option :vault, type: :string
      class_option :verbose, type: :boolean, default: false

      desc "login", "Run the OAuth 2.0 PKCE flow against X (or --browser for the no-dev-API browser source)"
      method_option :browser, type: :boolean, default: false,
                              desc: "Log in via a real browser instead of the dev API (no X_* credentials needed)"
      method_option :"accept-risk", type: :boolean, default: false,
                                    desc: "Accept the browser-source ToS/account-risk consent non-interactively (for scripts/agents)"
      def login
        return browser_login if options[:browser]

        require_relative "../config"
        require_relative "../x/auth"
        config = Xbookmark::Config.load(wiki_override: options[:wiki], vault_override: options[:vault], verbose: options[:verbose])
        result = Xbookmark::X::Auth.new(config).login
        warn "Logged in. Tokens written to #{result.env_file}." if result
      rescue Xbookmark::TransientAuthError => e
        warn "[xbookmark] #{redact_secret_like_values(e.message)}"
        warn "X token login is temporarily unavailable. Retry auth login later."
        exit 2
      rescue Xbookmark::AuthError => e
        warn "[xbookmark] #{redact_secret_like_values(e.message)}"
        warn "Run: xbookmark auth login"
        exit 1
      end

      desc "status", "Print the current X auth status"
      def status
        require_relative "../config"
        config = Xbookmark::Config.load(wiki_override: options[:wiki], vault_override: options[:vault], verbose: options[:verbose])
        source = (config.respond_to?(:source) && config.source) || Xbookmark::Config::SOURCE_API
        puts "source: #{source}"

        degraded_browser = false
        if Xbookmark::Config.browser_source?(source)
          degraded_browser = !browser_status
          if degraded_browser
            # The browser session IS the credential for the browser/both source.
            # Emit a stable, grep-able token (mirroring sync's SESSION_EXPIRED) so a
            # wrapper can detect "browser needs re-login" without scraping prose —
            # including in `both` mode, where the API half may still be healthy and
            # would otherwise leave this exiting 0 with prose-only output.
            warn "[xbookmark] BROWSER_SESSION_MISSING source=#{source}; re-run `xbookmark auth login --browser`."
          end
        end

        if Xbookmark::Config.api_source?(source)
          unless config.x_access_token && !config.x_access_token.empty?
            puts "Not logged in. Run: xbookmark auth login"
            exit 1
          end

          expires_at = config.x_token_expires_at
          if expires_at && expires_at <= Time.now.to_i
            puts "Access token expired at: #{format_timestamp(expires_at)}"
            if config.x_refresh_token && !config.x_refresh_token.empty?
              puts "Refresh token present. Run: xbookmark auth refresh"
            else
              puts "No refresh token. Run: xbookmark auth login"
            end
            exit 1
          end

          puts "Logged in. Token expires at: #{expires_at ? format_timestamp(expires_at) : "unknown"}"
        end

        # A degraded browser half exits non-zero even when the API half is fine, so
        # `browser` and `both` share the same non-zero "needs re-login" contract.
        exit 1 if degraded_browser
      end

      desc "refresh", "Refresh the saved X OAuth token"
      def refresh
        require_relative "../config"
        require_relative "../x/auth"
        config = Xbookmark::Config.load(wiki_override: options[:wiki], vault_override: options[:vault], verbose: options[:verbose])
        result = Xbookmark::X::Auth.new(config).refresh!
        warn "Refreshed. Tokens written to #{result.env_file}."
        warn "Token expires at: #{format_timestamp(result.expires_at.to_i)}"
      rescue Xbookmark::TransientAuthError => e
        warn "[xbookmark] #{redact_secret_like_values(e.message)}"
        warn "X token refresh is temporarily unavailable. Retry later."
        exit 2
      rescue Xbookmark::AuthError => e
        warn "[xbookmark] #{redact_secret_like_values(e.message)}"
        warn "Run: xbookmark auth login"
        exit 1
      end

      private

      def browser_login
        require_relative "../config"
        require_relative "../state/store"
        require_relative "../browser/login"
        # Browser login never needs the dev-API credentials, so load offline
        # (no required-key validation) regardless of the configured source.
        config = Xbookmark::Config.load_offline(wiki_override: options[:wiki], vault_override: options[:vault], verbose: options[:verbose])
        store = Xbookmark::State::Store.new(config.state_db_path)
        login = Xbookmark::Browser::Login.new(config: config, store: store, accept_risk: options[:"accept-risk"])
        exit 1 unless login.call
      rescue Xbookmark::Browser::ChromiumMissing => e
        # A missing system Chromium is the most common browser-login config error;
        # emit a grep-able token so an agent can branch straight to "install a browser".
        warn "[xbookmark] CHROMIUM_MISSING; #{e.message}"
        exit 1
      rescue Xbookmark::ConfigError => e
        # Any other ConfigError here is NOT a missing browser — load_offline also
        # parses XBOOKMARK_SOURCE and raises ConfigError for an invalid value, so
        # emit a distinct token rather than mislabeling it as CHROMIUM_MISSING.
        warn "[xbookmark] CONFIG_ERROR; #{e.message}"
        exit 1
      end

      # Returns true when a browser session profile has been persisted. This is a
      # browser-free file check (Session.profile_saved?), so it cannot vouch the
      # session is still logged in — say so rather than implying readiness.
      def browser_status
        require_relative "../browser/session"
        if Xbookmark::Browser::Session.profile_saved?
          # Re-assert 0700 on the profile (it holds live X cookies, > the OAuth
          # token); a chmod launches no browser, so this stays browser-free.
          Xbookmark::Browser::Session.secure_profile_dir!
          puts "browser session: profile saved but unverified (#{Xbookmark::Paths.browser_profile_dir}); " \
               "validity is confirmed at next sync"
          true
        else
          puts "browser session: none — run `xbookmark auth login --browser`"
          false
        end
      end

      SECRET_LIKE_VALUE = /[A-Za-z0-9_\-.~+\/=]{32,}/
      SECRET_FIELD = /
        \b(access_token|refresh_token|client_secret|authorization|token)
        (["']?\s*[:=]\s*["']?)
        [^"',}\s]+
      /ix

      def redact_secret_like_values(message)
        message.to_s
               .gsub(SECRET_FIELD, "\\1\\2[REDACTED]")
               .gsub(SECRET_LIKE_VALUE, "[REDACTED]")
      end

      def format_timestamp(value)
        "#{value} (#{Time.at(value.to_i).utc.iso8601})"
      end
    end
  end
end
