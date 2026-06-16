# frozen_string_literal: true

require "json"

module Xbookmark
  module Browser
    # Captures X's internal GraphQL response bodies from the real page's CDP
    # network traffic. The page issues genuine, authenticated requests (driven
    # by scrolling) — we never forge headers or the client transaction id — so
    # all X-shape knowledge stays here and in the Normalizer, keeping a future
    # endpoint change a localized fix.
    class GraphqlCapture
      GRAPHQL_PATH = "/i/api/graphql/"
      BOOKMARKS_OPERATION = "Bookmarks"
      TWEET_OPERATIONS = %w[TweetResultByRestId TweetDetail].freeze

      def initialize(page)
        @page = page
        @seen = {}
      end

      # Parsed JSON bodies of Bookmarks GraphQL responses not yet returned.
      def drain_bookmarks
        drain { |url| bookmarks_url?(url) }
      end

      # Parsed JSON bodies of single-tweet GraphQL responses not yet returned.
      def drain_tweets
        drain { |url| tweet_url?(url) }
      end

      private

      def drain
        traffic.filter_map do |exchange|
          url = exchange_url(exchange)
          next unless url && yield(url)

          key = exchange_key(exchange)
          next if @seen[key]

          @seen[key] = true
          parse(exchange)
        end
      end

      def traffic
        @page.network.traffic
      rescue StandardError
        []
      end

      def bookmarks_url?(url)
        url.include?(GRAPHQL_PATH) && url.include?("/#{BOOKMARKS_OPERATION}")
      end

      def tweet_url?(url)
        url.include?(GRAPHQL_PATH) && TWEET_OPERATIONS.any? { |op| url.include?("/#{op}") }
      end

      def exchange_url(exchange)
        exchange.request&.url
      rescue StandardError
        nil
      end

      def exchange_key(exchange)
        exchange.respond_to?(:id) ? exchange.id : exchange.object_id
      end

      def parse(exchange)
        body = response_body(exchange)
        return nil if body.to_s.empty?

        JSON.parse(body)
      rescue StandardError
        nil
      end

      def response_body(exchange)
        exchange.response&.body
      end
    end
  end
end
