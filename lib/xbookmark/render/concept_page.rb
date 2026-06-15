# frozen_string_literal: true

require "yaml"
require_relative "atomic_writer"
require_relative "bookmark_renderer"
require_relative "markdown_safety"
require_relative "wikilinks"

module Xbookmark
  module Render
    class ConceptPage
      def initialize(vault_path:, store: nil)
        @vault_path = vault_path
        @store = store
      end

      def ensure!(concept)
        path = page_path(concept.slug)
        content = render(concept)
        AtomicWriter.write(path, content)
        @store&.upsert_page(kind: "concept", slug: concept.slug, path: relativize(path))
        path
      end

      def page_path(slug)
        File.join(@vault_path, "concepts", "#{Wikilinks.slug(slug)}.md")
      end

      def render(concept)
        front = {
          "xbookmark_schema" => SCHEMA_VERSION,
          "kind" => "concept",
          "slug" => concept.slug,
          "label" => MarkdownSafety.frontmatter_string(concept.label),
          "concept_kind" => concept.kind,
          "aliases" => MarkdownSafety.alias_list(concept.aliases),
          "broader" => concept.broader,
          "tags" => MarkdownSafety.tags(concept.facets),
          "evidence_count" => concept.evidence_count,
          "confidence" => concept.confidence,
          "curator_outcome" => concept.outcome
        }
        broader = concept.broader.map { |slug| "- #{Wikilinks.link("concepts/#{slug}", label_for(slug))}" }
        body = ["# #{MarkdownSafety.wikilink_label(concept.label)}"]
        body << "## Broader\n\n#{broader.join("\n")}" unless broader.empty?
        body << "## References\n\n_Use Obsidian's Backlinks panel to see source notes for this concept._"
        "---\n#{front.to_yaml(line_width: -1).sub(/^---\n?/, "")}---\n\n#{body.join("\n\n")}\n"
      end

      private

      def label_for(slug)
        slug.to_s.split("-").map(&:capitalize).join(" ")
      end

      def relativize(path)
        prefix = @vault_path.to_s.sub(%r{/\z}, "")
        return path unless path.to_s.start_with?(prefix)

        path.to_s[(prefix.length + 1)..]
      end
    end
  end
end
