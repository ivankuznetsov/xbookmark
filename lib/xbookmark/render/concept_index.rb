# frozen_string_literal: true

require "yaml"
require_relative "atomic_writer"
require_relative "bookmark_renderer"
require_relative "wikilinks"

module Xbookmark
  module Render
    class ConceptIndex
      # Cap the root-concept list so the index stays a navigable entry point
      # rather than an alphabetical dump of every root once generic-root broader
      # links are stripped. The most-referenced roots are shown first.
      ROOT_DISPLAY_LIMIT = 200

      def initialize(vault_path:)
        @vault_path = vault_path
      end

      def write(concepts, conflicts: 0)
        path = File.join(@vault_path, "concepts", "index.md")
        AtomicWriter.write(path, render(concepts, conflicts: conflicts))
        path
      end

      def render(concepts, conflicts: 0)
        # "Orphan" means no broader link — the same definition the Auditor and
        # GraphHealthReport use, so the index and the health report agree.
        orphans = concepts.select { |concept| concept.broader.empty? }
        # Show the most-referenced roots first, capped for navigability.
        roots = orphans.sort_by { |concept| [-concept.evidence_count, concept.slug] }
        shown = roots.first(ROOT_DISPLAY_LIMIT)
        lines = ["# Concepts", "", "## Root Concepts"]
        lines += shown.map { |concept| "- #{Wikilinks.link("concepts/#{concept.slug}", concept.label)}" }
        lines << "- _…and #{roots.size - shown.size} more root concepts_" if roots.size > shown.size
        lines << ""
        lines << "## Graph Health"
        lines << ""
        lines << "- orphan_concepts: #{orphans.size}"
        lines << "- blocked_conflicts: #{conflicts}"
        "---\n#{frontmatter.to_yaml(line_width: -1).sub(/^---\n?/, "")}---\n\n#{lines.join("\n")}\n"
      end

      private

      def frontmatter
        { "xbookmark_schema" => SCHEMA_VERSION, "kind" => "concept_index", "slug" => "index" }
      end
    end
  end
end
