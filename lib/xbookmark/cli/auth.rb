# frozen_string_literal: true

require "thor"
require "time"

module Xbookmark
  class CLI
    class Auth < Thor
      class_option :wiki, type: :string
      class_option :vault, type: :string
      class_option :verbose, type: :boolean, default: false

      desc "login", "Run the OAuth 2.0 PKCE flow against X"
      def login
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
