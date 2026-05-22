# frozen_string_literal: true

require "fileutils"

module Xbookmark
  class Keystore
    # `.env`-file backend.  Used on Linux boxes with no D-Bus session
    # (headless servers) and as a last-resort fallback elsewhere.
    # The file is written with mode 0600 so the secrets are not group/
    # world-readable.
    class EnvFile
      attr_reader :path

      def initialize(path: nil)
        @path = path || default_path
      end

      def name
        "env_file (#{@path})"
      end

      def get(account)
        return nil unless File.file?(@path)
        env_key = Xbookmark::Keystore.env_key_for(account)
        read_all[env_key]
      end

      def set(account, value)
        env_key = Xbookmark::Keystore.env_key_for(account)
        entries = read_all
        entries[env_key] = value.to_s
        write_all(entries)
        true
      end

      def delete(account)
        env_key = Xbookmark::Keystore.env_key_for(account)
        entries = read_all
        return false unless entries.key?(env_key)
        entries.delete(env_key)
        write_all(entries)
        true
      end

      def list_accounts
        return [] unless File.file?(@path)
        read_all.keys.map { |k| Xbookmark::Keystore.account_for(k) }
      end

      private

      def default_path
        File.join(Xbookmark::Paths.default_config_dir, ".env")
      end

      def read_all
        return {} unless File.file?(@path)
        entries = {}
        File.read(@path).each_line do |line|
          line = line.chomp
          next if line.empty? || line.start_with?("#")
          k, _eq, v = line.partition("=")
          next if k.empty?
          # Strip surrounding quotes that dotenv-style writers add.
          # Inside double-quoted values, also unescape `\"` so secrets
          # containing literal `"` round-trip without growing backslashes.
          if (m = v.match(/\A"(.*)"\z/))
            v = m[1].gsub(/\\"/, '"')
          else
            v = v.sub(/\A'(.*)'\z/, '\1')
          end
          entries[k] = v
        end
        entries
      end

      def write_all(entries)
        FileUtils.mkdir_p(File.dirname(@path), mode: 0o700) unless File.directory?(File.dirname(@path))
        body = entries.map { |k, v| "#{k}=#{escape(v)}" }.join("\n")
        body += "\n" unless body.empty?
        # Write via tempfile + rename for atomicity, then chmod 0600.
        tmp = "#{@path}.tmp"
        File.write(tmp, body)
        File.chmod(0o600, tmp)
        File.rename(tmp, @path)
      end

      def escape(value)
        # Quote if the value has whitespace, '#' or trailing/leading space.
        if value.to_s.match?(/[\s#"]/)
          %("#{value.to_s.gsub('"', '\\"')}")
        else
          value.to_s
        end
      end
    end
  end
end
