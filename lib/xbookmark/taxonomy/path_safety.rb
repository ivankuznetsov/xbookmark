# frozen_string_literal: true

require "pathname"

module Xbookmark
  module Taxonomy
    class PathSafety
      ALLOWED_DIRS = %w[bookmarks authors concepts threads topics entities].freeze

      def initialize(vault_path:)
        @vault_path = File.expand_path(vault_path)
      end

      def allowed_markdown_files
        ALLOWED_DIRS.flat_map { |dir| Dir.glob(File.join(@vault_path, dir, "**", "*.md")) }
          .select { |path| safe_read_path?(path) }
      end

      def safe_read_path?(path)
        expanded = File.expand_path(path)
        relative = Pathname.new(expanded).relative_path_from(Pathname.new(@vault_path)).to_s
        ALLOWED_DIRS.any? { |dir| relative == dir || relative.start_with?("#{dir}/") } &&
          expanded.end_with?(".md") &&
          !File.symlink?(expanded)
      rescue ArgumentError
        false
      end

      def validate_write_path!(path)
        expanded = File.expand_path(path)
        raise ArgumentError, "path outside wiki root: #{path}" unless expanded.start_with?("#{@vault_path}/")
        raise ArgumentError, "refusing symlink target: #{path}" if File.symlink?(expanded)

        expanded
      end
    end
  end
end
