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
        @failures = 0
      end

      # Count of capture/parse failures across all drains. Lets the Source tell
      # a genuinely empty timeline (no matching responses) from a broken capture
      # (a CDP error, or an X response-shape change that no longer parses), so an
      # unattended run records a source error instead of silently exiting 0
      # "synced 0" while actually broken.
      attr_reader :failures

      def failures?
        @failures.positive?
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

          parsed = parse(exchange)
          # Only record the exchange as seen once it parses: a body that is still
          # empty/partial at capture time must be re-read on a later drain (after
          # it completes), not permanently skipped while the cursor advances.
          next if parsed.nil?

          @seen[key] = true
          parsed
        end
      end

      def traffic
        @page.network.traffic
      rescue StandardError
        @failures += 1
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
        # An empty body is "not ready yet", not a failure — return nil so drain
        # re-reads it later without counting it against the failure tally.
        return nil if body.to_s.empty?

        JSON.parse(body)
      rescue StandardError
        # A non-empty body that won't parse is a genuine capture failure (corrupt
        # response or a shape change), distinct from an empty/absent body.
        @failures += 1
        nil
      end

      def response_body(exchange)
        exchange.response&.body
      end
    end
  end
end
