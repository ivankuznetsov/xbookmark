# frozen_string_literal: true

require "fileutils"

module Xbookmark
  class CodexConfig
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
      File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |file| file.write(updated) }
      File.chmod(0o600, path)
      true
    end

    def self.without_service_tier(content)
      lines = content.lines
      table_index = lines.find_index { |line| line.match?(/\A\s*\[/) } || lines.length

      top_level_key_index = lines[0...table_index].find_index { |line| line.match?(/\A\s*service_tier\s*=/) }
      lines.delete_at(top_level_key_index) if top_level_key_index
      lines.join
    end
  end
end
