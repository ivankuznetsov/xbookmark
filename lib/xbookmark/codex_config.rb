# frozen_string_literal: true

require "fileutils"
require "securerandom"

module Xbookmark
  class CodexConfig
    STALE_SERVICE_TIER_VALUES = %w[default flex].freeze

    attr_reader :path

    def initialize(path: nil)
      @path = path || self.class.default_path
    end

    def self.default_path
      home = ENV["CODEX_HOME"].to_s.empty? ? File.join(Dir.home, ".codex") : ENV["CODEX_HOME"]
      File.join(home, "config.toml")
    end

    def remove_service_tier_override!
      current = File.exist?(path) ? File.read(path) : ""
      updated = self.class.without_service_tier(current)
      return false if updated == current

      FileUtils.mkdir_p(File.dirname(path))
      atomic_write(updated)
      true
    end

    def self.without_service_tier(content)
      lines = content.lines
      table_index = lines.find_index { |line| line.match?(/\A\s*\[/) } || lines.length

      lines.each_with_index.reject { |(line, index)| index < table_index && stale_service_tier?(line) }
           .map(&:first)
           .join
    end

    def self.stale_service_tier?(line)
      match = line.match(/\A\s*service_tier\s*=\s*(?:"([^"]+)"|'([^']+)'|([A-Za-z0-9_-]+))/)
      return false unless match

      STALE_SERVICE_TIER_VALUES.include?((match[1] || match[2] || match[3]).to_s)
    end

    private

    def atomic_write(content)
      tmp_path = File.join(File.dirname(path), ".#{File.basename(path)}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp")
      File.open(tmp_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.rename(tmp_path, path)
      File.chmod(0o600, path)
    ensure
      File.delete(tmp_path) if tmp_path && File.exist?(tmp_path)
    end
  end
end
