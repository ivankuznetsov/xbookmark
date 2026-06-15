# frozen_string_literal: true

require_relative "../taxonomy/concept"
require_relative "../taxonomy/prompt_context"
require_relative "../taxonomy/registry"

module Xbookmark
  module Enrich
    class PromptContext
      def initialize(registry: nil, existing_slugs: [], byte_limit: Xbookmark::Taxonomy::PromptContext::DEFAULT_BYTE_LIMIT)
        @registry = registry || registry_from_slugs(existing_slugs)
        @byte_limit = byte_limit
      end

      def to_json_for(labels)
        Xbookmark::Taxonomy::PromptContext.new(registry: @registry, byte_limit: @byte_limit).to_json_for(labels)
      end

      private

      def registry_from_slugs(slugs)
        concepts = Array(slugs).map { |slug| Xbookmark::Taxonomy::Concept.new(slug: slug) }
        Xbookmark::Taxonomy::Registry.new(concepts)
      end
    end
  end
end
