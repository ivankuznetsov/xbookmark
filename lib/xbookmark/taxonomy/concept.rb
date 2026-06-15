# frozen_string_literal: true

require_relative "../render/markdown_safety"
require_relative "../render/wikilinks"

module Xbookmark
  module Taxonomy
    class Concept
      DEFAULT_KIND = "idea"
      DEFAULT_OUTCOME = "canonical"
      # The single closed kind vocabulary, shared by the enrichment prompt, the
      # normalizer, and the curator. Any kind outside this set (including the
      # legacy migration kinds) is coerced to a canonical value so `kind` is a
      # reliable queryable Property.
      KINDS = %w[area subtopic entity technology place organization idea].freeze
      KIND_ALIASES = { "topic" => "idea", "concept" => "idea", "org" => "organization" }.freeze

      attr_reader :slug, :label, :kind, :aliases, :broader, :facets, :evidence_count,
                  :confidence, :outcome

      def initialize(slug:, label: nil, kind: DEFAULT_KIND, aliases: [], broader: [], facets: [],
                     evidence_count: 1, confidence: nil, outcome: DEFAULT_OUTCOME)
        @slug = Xbookmark::Render::Wikilinks.slug(slug)
        @label = Xbookmark::Render::MarkdownSafety.frontmatter_string(label || titleize(@slug)) || @slug
        @kind = canonical_kind(kind)
        @aliases = Xbookmark::Render::MarkdownSafety.alias_list(aliases).freeze
        @broader = Array(broader).map { |parent| Xbookmark::Render::Wikilinks.slug(parent) }.reject(&:empty?).uniq.freeze
        @facets = Xbookmark::Render::MarkdownSafety.tags(facets).freeze
        @evidence_count = evidence_count.to_i
        # Clamp on both branches so an explicit out-of-range confidence
        # (e.g. a corrupt frontmatter value) can never leak into the registry
        # or the confidence gate.
        @confidence = (confidence.nil? ? confidence_from_evidence(@evidence_count) : confidence.to_f).clamp(0.0, 1.0)
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

      # Coerce any kind (LLM output, legacy migration value, malformed string)
      # into the closed KINDS set; legacy/aliased kinds map through KIND_ALIASES.
      def canonical_kind(kind)
        cleaned = Xbookmark::Render::MarkdownSafety.frontmatter_string(kind)&.downcase
        return DEFAULT_KIND if cleaned.nil? || cleaned.empty?

        mapped = KIND_ALIASES.fetch(cleaned, cleaned)
        KINDS.include?(mapped) ? mapped : DEFAULT_KIND
      end

      def confidence_from_evidence(count)
        [[count.to_i, 10].min / 10.0, 0.1].max
      end
    end
  end
end
