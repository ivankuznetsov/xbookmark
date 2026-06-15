# frozen_string_literal: true

require_relative "normalizer"
require_relative "prompt_context"
require_relative "states"

module Xbookmark
  module Taxonomy
    # Deterministic taxonomy curation layer. `curate` normalizes candidates,
    # gates low-confidence concepts as blocked conflicts, and (when a store is
    # given) persists both the concept row and an audit entry in
    # `curator_decisions`. This is the entry point reserved for the LLM-driven
    # scheduled curation step; the per-bookmark sync path uses Normalizer
    # directly. It is not yet wired into the live run.
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
        state = concept.confidence < MIN_CONFIDENCE ? States::BLOCKED_CONFLICTS : concept.outcome
        concept.to_h.merge("curation_state" => state)
      end

      # Persistence is optional: `curate` always returns the decisions, and the
      # store write only runs when a store was provided. The audit log entry
      # keeps blocked-conflict decisions inspectable rather than discarding them.
      def persist(decision)
        return unless @store

        @store.upsert_concept(
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
        @store.record_curator_decision(slug: decision["slug"], decision: decision)
      end
    end
  end
end
