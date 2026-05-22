# frozen_string_literal: true

require "dotenv"
require_relative "../keystore"

module Xbookmark
  class Keystore
    # One-way migration helper.  Reads keys from an existing `.env`
    # file and writes them into a Keystore.  Never deletes the source.
    class Importer
      def initialize(keystore: Keystore.default)
        @keystore = keystore
      end

      # Returns the list of env keys (uppercase form) that were
      # migrated into the keystore.  Skips keys whose value is empty
      # or that are not in `Keystore::KNOWN_KEYS`.
      def import(env_path)
        return [] unless File.file?(env_path)
        parsed = ::Dotenv.parse(env_path)
        migrated = []
        Keystore::KNOWN_KEYS.each do |account|
          env_key = Keystore.env_key_for(account)
          value = parsed[env_key]
          next if value.nil? || value.to_s.strip.empty?
          @keystore.set(account, value)
          migrated << env_key
        end
        migrated
      end
    end
  end
end
