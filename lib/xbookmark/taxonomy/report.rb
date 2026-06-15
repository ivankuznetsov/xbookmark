# frozen_string_literal: true

module Xbookmark
  module Taxonomy
    class Report
      EXIT_CODES = {
        "clean" => 0,
        "proposed_changes" => 1,
        "blocked_conflicts" => 2,
        "applied" => 0,
        "partial_failure" => 3
      }.freeze

      attr_reader :state, :counts, :manifest_path, :graph_health_path, :skipped

      def initialize(state:, counts: {}, manifest_path: nil, graph_health_path: nil, skipped: [])
        @state = state.to_s
        @counts = counts
        @manifest_path = manifest_path
        @graph_health_path = graph_health_path
        @skipped = skipped
      end

      def exit_code
        EXIT_CODES.fetch(state)
      end

      def clean?
        state == "clean"
      end

      def to_s
        parts = ["taxonomy: #{state}"]
        parts << "counts=#{counts}" unless counts.empty?
        parts << "manifest=#{manifest_path}" if manifest_path
        parts << "report=#{graph_health_path}" if graph_health_path
        parts << "skipped=#{skipped.join(',')}" unless skipped.empty?
        parts.join(" ")
      end
    end
  end
end
