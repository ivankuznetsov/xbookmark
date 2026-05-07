# frozen_string_literal: true

require "faraday"
require "nokogiri"
require "time"

module Xbookmark
  module Enrich
    class LinkFetcher
      def initialize(conn: nil)
        @conn = conn
      end

      # Returns { url:, final_url:, title:, byline:, text:, fetched_at: } or
      # nil when fetch fails.
      def fetch(url)
        res = http.get(url) { |req| req.options.timeout = 20 }
        return nil unless res.success?
        doc = Nokogiri::HTML(res.body)
        title = doc.at("title")&.text&.strip
        byline = doc.at('meta[name="author"]')&.[]("content")
        body_nodes = doc.css("article p, main p, p")
        text = body_nodes.map(&:text).join("\n\n").strip[0, 8000]
        {
          url: url,
          final_url: res.env.url.to_s,
          title: title,
          byline: byline,
          text: text,
          fetched_at: Time.now.utc.iso8601
        }
      rescue StandardError
        nil
      end

      private

      def http
        @conn ||= Faraday.new do |f|
          f.headers["User-Agent"] = "xbookmark/1.0 (link-readability-fetcher)"
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
