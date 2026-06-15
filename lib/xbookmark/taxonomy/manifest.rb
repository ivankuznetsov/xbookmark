# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

module Xbookmark
  module Taxonomy
    class Manifest
      attr_reader :path, :operations

      def initialize(path:)
        @path = path
        @operations = []
      end

      def add(type, payload)
        @operations << payload.merge("type" => type.to_s)
      end

      def write(snapshot_path: nil, graph_health_path: nil)
        FileUtils.mkdir_p(File.dirname(path))
        body = {
          "created_at" => Time.now.utc.iso8601,
          "snapshot_path" => snapshot_path,
          "graph_health_path" => graph_health_path,
          "operations" => operations
        }
        body["manifest_hash"] = Digest::SHA256.hexdigest(JSON.generate(body))
        File.write(path, JSON.pretty_generate(body))
        path
      end
    end
  end
end
