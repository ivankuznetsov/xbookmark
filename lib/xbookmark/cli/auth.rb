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
        if Xbookmark::Config.browser_source?(source)
          browser_present = browser_status
          # In browser-only mode the browser session IS the credential; mirror
          # the API branch's `exit 1` so a wrapper can detect "needs re-login"
          # without scraping prose, instead of always reporting success.
          exit 1 if source == Xbookmark::Config::SOURCE_BROWSER && !browser_present
        end
        return unless Xbookmark::Config.api_source?(source)

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
      rescue Xbookmark::ConfigError => e
        warn "[xbookmark] #{e.message}"
        exit 1
      end

      # Returns true when a browser session profile has been persisted. This is a
      # browser-free file check (Session.profile_saved?), so it cannot vouch the
      # session is still logged in — say so rather than implying readiness.
      def browser_status
        require_relative "../browser/session"
        if Xbookmark::Browser::Session.profile_saved?
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
