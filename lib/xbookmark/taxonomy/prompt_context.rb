# frozen_string_literal: true

require "json"
require_relative "registry"
require_relative "../render/markdown_safety"

module Xbookmark
  module Taxonomy
    class PromptContext
      DEFAULT_BYTE_LIMIT = 4_000

      def initialize(registry:, byte_limit: DEFAULT_BYTE_LIMIT, alias_limit: 5)
        @registry = registry
        @byte_limit = byte_limit
        @alias_limit = alias_limit
      end

      def for_labels(labels, limit: 20)
        concepts = @registry.relevant(labels, limit: limit)
        payload = concepts.map { |concept| serialize(concept) }
        trim_to_limit(payload)
      end

      def to_json_for(labels, limit: 20)
        JSON.generate(for_labels(labels, limit: limit))
      end

      private

      def serialize(concept)
        {
          "slug" => safe(concept.slug),
          "label" => safe(concept.label),
          "kind" => safe(concept.kind),
          "aliases" => concept.aliases.first(@alias_limit).map { |value| safe(value) },
          "parents" => concept.broader.first(5).map { |value| safe(value) },
          "evidence_count" => concept.evidence_count
        }
      end

      def safe(value)
        Xbookmark::Render::MarkdownSafety.prompt_field(value)
      end

      def trim_to_limit(payload)
        kept = []
        payload.each do |row|
          next_row = kept + [row]
          break if JSON.generate(next_row).bytesize > @byte_limit

          kept = next_row
        end
        kept
      end
    end
  end
end
