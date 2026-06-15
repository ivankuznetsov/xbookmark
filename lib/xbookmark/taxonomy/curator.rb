# frozen_string_literal: true

require_relative "normalizer"
require_relative "prompt_context"

module Xbookmark
  module Taxonomy
    class Curator
      MIN_CONFIDENCE = 0.3

      def initialize(codex: nil, registry: Registry.new, normalizer: nil, store: nil)
        @codex = codex
        @registry = registry
        @normalizer = normalizer || Normalizer.new(registry: registry)
        @store = store
      end

      def curate(candidates)
        concepts = @normalizer.normalize_candidates(candidates)
        decisions = concepts.map { |concept| decision_for(concept) }
        decisions.each { |decision| persist(decision) }
        decisions
      end

      def prompt_for(candidates)
        labels = Array(candidates).map { |candidate| candidate.is_a?(Hash) ? candidate["label"] || candidate[:label] : candidate }
        context = PromptContext.new(registry: @registry).to_json_for(labels)
        "Resolve taxonomy candidates using only this sanitized registry context:\n#{context}"
      end

      private

      def decision_for(concept)
        state = concept.confidence < MIN_CONFIDENCE ? "blocked_conflict" : concept.outcome
        concept.to_h.merge("curation_state" => state)
      end

      def persist(decision)
        @store&.upsert_concept(
          slug: decision["slug"],
          label: decision["label"],
          kind: decision["kind"],
          aliases: decision["aliases"],
          broader: decision["broader"],
          facets: decision["facets"],
          evidence_count: decision["evidence_count"],
          confidence: decision["confidence"],
          curator_outcome: decision["curation_state"]
        )
      end
    end
  end
end
