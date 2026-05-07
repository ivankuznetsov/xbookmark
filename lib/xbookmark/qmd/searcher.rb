# frozen_string_literal: true

require "open3"
require "json"
require_relative "registrar"

module Xbookmark
  module Qmd
    class Searcher
      def initialize(config:, runner: nil)
        @config = config
        @runner = runner
      end

      # Returns array of { path:, score:, snippet: }.
      def search(query, limit: 20)
        argv = [@config.qmd_bin, "query",
                "--collection", Registrar::COLLECTION_NAME,
                "--types", "lex,vec",
                "--limit", limit.to_s,
                "--json", query]

        out, err, status = capture(argv)
        unless status_success?(status)
          warn "[xbookmark] qmd query failed: #{err}"
          return []
        end
        parse(out)
      rescue Errno::ENOENT
        warn "[xbookmark] qmd binary not found at #{@config.qmd_bin}; install qmd or set QMD_BIN."
        []
      end

      private

      def capture(argv)
        if @runner
          @runner.call(argv)
        else
          Open3.capture3(*argv)
        end
      end

      def status_success?(status)
        status.respond_to?(:success?) ? status.success? : status == 0
      end

      def parse(raw)
        body = raw.strip
        return [] if body.empty?
        json = JSON.parse(body)
        results = json.is_a?(Array) ? json : (json["results"] || json["hits"] || [])
        results.map do |r|
          {
            path: r["path"] || r["file"],
            score: (r["score"] || r["rank"]).to_f,
            snippet: r["snippet"] || r["context"]
          }
        end
      rescue JSON::ParserError
        []
      end
    end
  end
end
