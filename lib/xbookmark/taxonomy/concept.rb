# frozen_string_literal: true

require_relative "../render/markdown_safety"
require_relative "../render/wikilinks"

module Xbookmark
  module Taxonomy
    class Concept
      DEFAULT_KIND = "idea"
      DEFAULT_OUTCOME = "canonical"

      attr_reader :slug, :label, :kind, :aliases, :broader, :facets, :evidence_count,
                  :confidence, :outcome

      def initialize(slug:, label: nil, kind: DEFAULT_KIND, aliases: [], broader: [], facets: [],
                     evidence_count: 1, confidence: nil, outcome: DEFAULT_OUTCOME)
        @slug = Xbookmark::Render::Wikilinks.slug(slug)
        @label = Xbookmark::Render::MarkdownSafety.frontmatter_string(label || titleize(@slug)) || @slug
        @kind = Xbookmark::Render::MarkdownSafety.frontmatter_string(kind) || DEFAULT_KIND
        @aliases = Xbookmark::Render::MarkdownSafety.alias_list(aliases)
        @broader = Array(broader).map { |parent| Xbookmark::Render::Wikilinks.slug(parent) }.reject(&:empty?).uniq
        @facets = Xbookmark::Render::MarkdownSafety.tags(facets)
        @evidence_count = evidence_count.to_i
        @confidence = confidence.nil? ? confidence_from_evidence(@evidence_count) : confidence.to_f
        @outcome = Xbookmark::Render::MarkdownSafety.frontmatter_string(outcome) || DEFAULT_OUTCOME
      end

      def canonical?
        outcome == DEFAULT_OUTCOME
      end

      def to_h
        {
          "slug" => slug,
          "label" => label,
          "kind" => kind,
          "aliases" => aliases,
          "broader" => broader,
          "facets" => facets,
          "evidence_count" => evidence_count,
          "confidence" => confidence,
          "curator_outcome" => outcome
        }
      end

      private

      def titleize(slug)
        slug.to_s.split("-").map(&:capitalize).join(" ")
      end

      def confidence_from_evidence(count)
        [[count.to_i, 10].min / 10.0, 0.1].max
      end
    end
  end
end
