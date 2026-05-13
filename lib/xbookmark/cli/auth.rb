# frozen_string_literal: true

require "thor"

module Xbookmark
  class CLI
    class Auth < Thor
      class_option :vault, type: :string
      class_option :verbose, type: :boolean, default: false

      desc "login", "Run the OAuth 2.0 PKCE flow against X"
      def login
        require_relative "../config"
        require_relative "../x/auth"
        config = Xbookmark::Config.load(vault_override: options[:vault], verbose: options[:verbose])
        result = Xbookmark::X::Auth.new(config).login
        warn "Logged in. Tokens written to #{result.env_file}." if result
      end

      desc "status", "Print the current X auth status"
      def status
        require_relative "../config"
        config = Xbookmark::Config.load(vault_override: options[:vault], verbose: options[:verbose])
        if config.x_access_token && !config.x_access_token.empty?
          puts "Logged in. Token expires at: #{config.x_token_expires_at || "unknown"}"
        else
          puts "Not logged in. Run: xbookmark auth login"
          exit 1
        end
      end
    end
  end
end
