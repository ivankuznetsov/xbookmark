# frozen_string_literal: true

require "open3"

module Xbookmark
  class Keystore
    # macOS Keychain backend.  Shells out to `security` from Apple's
    # Security framework.
    class Keychain
      SERVICE = "xbookmark"

      def self.available?
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
          full = File.join(dir, "security")
          return true if File.executable?(full) && !File.directory?(full)
        end
        false
      end

      def name
        "keychain"
      end

      def get(account)
        out, _err, status = Open3.capture3(
          "security", "find-generic-password",
          "-s", SERVICE, "-a", account.to_s, "-w"
        )
        return nil unless status.success?
        value = out.to_s.chomp
        value.empty? ? nil : value
      end

      def set(account, value)
        # -U updates if it already exists; -w sets the value.  We pass the
        # value via -w on the command line because `security` does not read
        # generic passwords from stdin.  This is the same shape used by the
        # macOS Keychain CLI throughout Apple's own docs.
        _out, err, status = Open3.capture3(
          "security", "add-generic-password",
          "-s", SERVICE,
          "-a", account.to_s,
          "-w", value.to_s,
          "-U"
        )
        return true if status.success?
        raise Xbookmark::Error, "security add-generic-password failed: #{err}"
      end

      def delete(account)
        _out, _err, status = Open3.capture3(
          "security", "delete-generic-password",
          "-s", SERVICE, "-a", account.to_s
        )
        status.success?
      end

      def list_accounts
        # `security` cannot enumerate all items for a service in a stable
        # parseable form, so we probe the known account list and report
        # which ones exist.
        Xbookmark::Keystore::KNOWN_KEYS.select { |a| !get(a).nil? }
      end
    end
  end
end
