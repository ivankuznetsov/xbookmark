# frozen_string_literal: true

module Xbookmark
  class Keystore
    # In-memory keystore. Used in tests and as an injection point for
    # callers that want to pre-seed values without touching the real
    # platform keychain or `.env` file.
    class Memory
      def self.available?
        true
      end

      def initialize(initial = {})
        @data = initial.dup
      end

      def name
        "memory"
      end

      def get(account)
        @data[account.to_s]
      end

      def set(account, value)
        @data[account.to_s] = value.to_s
        true
      end

      def delete(account)
        @data.delete(account.to_s) ? true : false
      end

      def list_accounts
        @data.keys
      end

      def to_h
        @data.dup
      end
    end
  end
end
