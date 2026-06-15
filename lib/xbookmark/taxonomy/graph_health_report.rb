# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "report"

module Xbookmark
  module Taxonomy
    class GraphHealthReport
      SOURCE_DOMINANCE_LIMIT = 20.0
      ORPHAN_RATIO_LIMIT = 0.8

      attr_reader :before, :after

      def initialize(before:, after: nil)
        @before = before
        @after = after || before
      end

      def ready?
        after.fetch(:numeric_bookmark_nodes, 0).zero? &&
          after.fetch(:singleton_thread_pages, 0).zero? &&
          orphan_ratio <= ORPHAN_RATIO_LIMIT &&
          source_note_dominance <= SOURCE_DOMINANCE_LIMIT
      end

      def to_h
        {
          "ready" => ready?,
          "before" => stringify(before),
          "after" => stringify(after),
          "thresholds" => {
            "numeric_bookmark_nodes" => 0,
            "singleton_thread_pages" => 0,
            "orphan_ratio_max" => ORPHAN_RATIO_LIMIT,
            "source_note_dominance_max" => SOURCE_DOMINANCE_LIMIT
          }
        }
      end

      def write(path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(to_h))
        path
      end

      private

      def orphan_ratio
        concepts = after.fetch(:concept_pages, 0).to_f
        return 0.0 if concepts.zero?

        after.fetch(:orphan_concepts, 0).to_f / concepts
      end

      def source_note_dominance
        concepts = after.fetch(:concept_pages, 0).to_f
        return 0.0 if concepts.zero? && after.fetch(:source_notes, 0).zero?
        return Float::INFINITY if concepts.zero?

        after.fetch(:source_notes, 0).to_f / concepts
      end

      def stringify(hash)
        hash.transform_keys(&:to_s)
      end
    end
  end
end
