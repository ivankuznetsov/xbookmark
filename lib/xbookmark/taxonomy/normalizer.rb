# frozen_string_literal: true

require_relative "concept"
require_relative "registry"

module Xbookmark
  module Taxonomy
    class Normalizer
      DEFAULT_RECURRENCE_THRESHOLD = 3
      DEMONYMS = { "venezuelan" => "venezuela" }.freeze
      ACRONYMS = { "attention-deficit-hyperactivity-disorder" => "adhd" }.freeze
      FACET_PARENTS = {
        "politics" => "politics",
        "economy" => "economics",
        "economics" => "economics",
        "oil" => "oil"
      }.freeze

      def initialize(registry: Registry.new, recurrence_counts: {}, recurrence_threshold: DEFAULT_RECURRENCE_THRESHOLD)
        @registry = registry
        @recurrence_counts = recurrence_counts.transform_keys { |key| canonical_slug(key) }
        @recurrence_threshold = recurrence_threshold.to_i
      end

      def normalize_candidates(candidates)
        Array(candidates).flat_map { |candidate| normalize(candidate) }
          .each_with_object({}) { |concept, out| out[concept.slug] ||= concept }
          .values
      end

      def normalize(candidate)
        attrs = candidate_attrs(candidate)
        slug = canonical_slug(attrs[:label])
        stored = @registry.find(slug)
        return [stored] if stored
        return split_conjunction(slug) if one_off_conjunction?(slug)
        return split_low_recurrence_compound(slug) if low_recurrence_child?(slug)

        [concept_for(slug, kind: attrs[:kind], aliases: attrs[:aliases], broader: attrs[:broader])]
      end

      def canonical_slug(value)
        slug = Xbookmark::Render::Wikilinks.slug(value).sub(/-+\z/, "")
        slug = ACRONYMS.fetch(slug, slug)
        DEMONYMS.each { |from, to| slug = slug.gsub(/\b#{from}\b/, to) }
        slug.empty? ? "untitled" : slug
      end

      private

      def candidate_attrs(candidate)
        return { label: candidate, kind: "idea", aliases: [], broader: [] } unless candidate.is_a?(Hash)

        {
          label: candidate["label"] || candidate[:label] || candidate["slug"] || candidate[:slug],
          kind: candidate["kind"] || candidate[:kind] || "idea",
          aliases: Array(candidate["aliases"] || candidate[:aliases]),
          broader: Array(candidate["broader"] || candidate[:broader])
        }
      end

      def one_off_conjunction?(slug)
        slug.include?("-and-") && recurrence_for(slug) < @recurrence_threshold
      end

      def low_recurrence_child?(slug)
        root, child = split_parent_child(slug)
        root && child && recurrence_for(slug) < @recurrence_threshold
      end

      def split_conjunction(slug)
        slug.split("-and-").flat_map { |part| normalize(part) }
      end

      def split_low_recurrence_compound(slug)
        root, child = split_parent_child(slug)
        [concept_for(root, kind: "place"), concept_for(FACET_PARENTS[child] || child, kind: "area")]
      end

      def concept_for(slug, kind:, aliases: [], broader: [])
        root, child = split_parent_child(slug)
        explicit_broader = Array(broader).map { |parent| canonical_slug(parent) }.reject(&:empty?)
        broader = if explicit_broader.empty? && root && child
                    [root, FACET_PARENTS[child] || child]
                  else
                    explicit_broader
                  end
        facets = facets_for(slug, root, child)
        Concept.new(slug: slug, label: label_for(slug), kind: kind, aliases: aliases, broader: broader, facets: facets,
                    evidence_count: recurrence_for(slug))
      end

      def split_parent_child(slug)
        first, *rest = slug.split("-")
        return [nil, nil] if rest.empty? || !%w[venezuela].include?(first)

        [first, rest.join("-")]
      end

      def facets_for(slug, root, child)
        facets = []
        facets << "area/#{root}" if root
        facets << "facet/#{FACET_PARENTS[child] || child}" if child
        facets << "concept/#{slug}"
        facets
      end

      def recurrence_for(slug)
        @recurrence_counts[canonical_slug(slug)].to_i
      end

      def label_for(slug)
        slug.split("-").map { |part| part == "adhd" ? "ADHD" : part.capitalize }.join(" ")
      end
    end
  end
end
