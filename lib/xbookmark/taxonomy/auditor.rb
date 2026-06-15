# frozen_string_literal: true

require "yaml"
require_relative "path_safety"
require_relative "report"

module Xbookmark
  module Taxonomy
    class Auditor
      # Metric keys that, when any is positive, mean the wiki has repairable
      # taxonomy debt. Shared with Rebuilder so the audit gate and the apply
      # gate cannot drift apart.
      ACTIONABLE_KEYS = %i[numeric_bookmark_nodes singleton_thread_pages].freeze

      def initialize(vault_path:)
        @vault_path = vault_path
        @safety = PathSafety.new(vault_path: vault_path)
      end

      def call
        counts = metrics
        state = actionable?(counts) ? "proposed_changes" : "clean"
        Report.new(state: state, counts: counts)
      end

      def metrics
        files = @safety.allowed_markdown_files
        concept_frontmatter = files.select { |path| path.include?("/concepts/") && File.basename(path) != "index.md" }.map { |path| frontmatter(path) }
        {
          numeric_bookmark_nodes: numeric_bookmarks(files),
          singleton_thread_pages: numeric_threads(files),
          one_off_compound_topics: compound_topics(files),
          duplicate_alias_clusters: duplicate_alias_clusters(concept_frontmatter),
          orphan_concepts: orphan_concepts(concept_frontmatter),
          source_notes: files.count { |path| path.include?("/bookmarks/") },
          concept_pages: concept_frontmatter.size
        }
      end

      private

      def actionable?(counts)
        counts.values_at(*ACTIONABLE_KEYS).any?(&:positive?)
      end

      def numeric_bookmarks(files)
        files.count { |path| path.include?("/bookmarks/") && File.basename(path, ".md").match?(/\A\d+\z/) }
      end

      def numeric_threads(files)
        files.count { |path| path.include?("/threads/") && File.basename(path, ".md").match?(/\A\d+\z/) }
      end

      def compound_topics(files)
        files.count do |path|
          next false unless path.include?("/topics/")

          slug = File.basename(path, ".md")
          slug.end_with?("-") || slug.split("-").size >= 3
        end
      end

      def duplicate_alias_clusters(frontmatter)
        aliases = Hash.new(0)
        frontmatter.each { |front| Array(front["aliases"]).each { |alias_name| aliases[alias_name.to_s.downcase] += 1 } }
        aliases.values.count { |count| count > 1 }
      end

      def orphan_concepts(frontmatter)
        frontmatter.count { |front| Array(front["broader"]).empty? }
      end

      def frontmatter(path)
        raw = File.read(path)
        return {} unless raw.start_with?("---\n")

        front = YAML.safe_load(raw.split("---\n", 3)[1], aliases: false)
        front.is_a?(Hash) ? front : {}
      rescue Psych::Exception
        {}
      end
    end
  end
end
