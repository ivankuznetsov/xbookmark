# frozen_string_literal: true

require "date"
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
      # Slugs used as synthetic top-level roots during migration; a concept
      # whose only `broader` is one of these has no real hierarchy.
      GENERIC_ROOTS = %w[topics entities].freeze

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
          legacy_pages: legacy_pages(files),
          concepts_with_real_broader: concepts_with_real_broader(concept_frontmatter),
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

      # Surviving legacy aux pages after a repair should be zero; any remaining
      # topics/entities page means the migration did not finish.
      def legacy_pages(files)
        files.count { |path| path.include?("/topics/") || path.include?("/entities/") }
      end

      # A concept has "real" hierarchy when it has at least one broader parent
      # that is not a synthetic generic root.
      def concepts_with_real_broader(frontmatter)
        frontmatter.count { |front| (Array(front["broader"]).map(&:to_s) - GENERIC_ROOTS).any? }
      end

      def frontmatter(path)
        raw = File.read(path)
        return {} unless raw.start_with?("---\n")

        front = YAML.safe_load(raw.split("---\n", 3)[1], permitted_classes: [Date, Time], aliases: false)
        front.is_a?(Hash) ? front : {}
      rescue Psych::Exception
        {}
      end
    end
  end
end
