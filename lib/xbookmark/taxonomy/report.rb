# frozen_string_literal: true

require_relative "states"

module Xbookmark
  module Taxonomy
    class Report
      EXIT_CODES = States::EXIT_CODES

      attr_reader :state, :counts, :manifest_path, :graph_health_path, :snapshot_path, :skipped

      def initialize(state:, counts: {}, manifest_path: nil, graph_health_path: nil, snapshot_path: nil, skipped: [])
        @state = state.to_s
        raise ArgumentError, "unknown taxonomy report state: #{@state}" unless EXIT_CODES.key?(@state)

        @counts = counts
        @manifest_path = manifest_path
        @graph_health_path = graph_health_path
        @snapshot_path = snapshot_path
        @skipped = skipped
      end

      def exit_code
        EXIT_CODES.fetch(state)
      end

      def clean?
        state == "clean"
      end

      def partial_failure?
        state == "partial_failure"
      end

      def to_s
        parts = ["taxonomy: #{state}"]
        parts << "counts=#{counts}" unless counts.empty?
        parts << "manifest=#{manifest_path}" if manifest_path
        parts << "report=#{graph_health_path}" if graph_health_path
        parts << "snapshot=#{snapshot_path}" if snapshot_path
        parts << "skipped=#{skipped.join(',')}" unless skipped.empty?
        parts.join(" ")
      end
    end
  end
end
