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
        # High-water mark into the cumulative CDP traffic buffer (`network.traffic`
        # only ever grows). Exchanges before this index are fully settled and are
        # never re-inspected, so a long backfill (the ~4,745-bookmark account)
        # stays O(total exchanges) instead of re-walking the whole growing buffer
        # on every drain — which was O(n²) and could burn toward RuntimeMaxSec.
        @scanned = 0
        @failures = 0
        # True once a matching GraphQL exchange has been observed at all (even one
        # whose body never filled), so the Source can tell "endpoint observed but
        # empty" (transient) from "endpoint never seen" (a walled/expired session).
        @observed = false
      end

      # True when at least one capture/parse failure has been tallied. This is
      # what flips a run to SessionExpired vs TransientError, so it lets the Source
      # tell a genuinely empty timeline (no matching responses) from a broken
      # capture (a CDP error, or an X response-shape change that no longer parses).
      def failures?
        @failures.positive?
      end

      # True when at least one exchange matching the active operation was seen this
      # capture, regardless of whether its body ever parsed. Distinguishes an
      # observed-but-unfilled endpoint (transient) from one never seen (expired).
      def observed?
        @observed
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
        buffer = traffic
        results = []
        high_water = @scanned
        blocked = false
        index = @scanned
        while index < buffer.size
          state, parsed = classify(buffer[index]) { |url| yield url }
          results << parsed if state == :parsed
          # Advance the high-water mark only across the leading run of settled
          # exchanges; a matching exchange whose body has not arrived yet
          # (:pending) must be re-read on a later drain (after it completes), so
          # stop advancing there — but keep scanning the rest of this drain so an
          # already-complete exchange behind it is still returned (and deduped via
          # @seen so it is never yielded twice).
          if state == :pending
            blocked = true
          elsif !blocked
            high_water = index + 1
          end
          index += 1
        end
        @scanned = high_water
        results
      end

      # Classifies one exchange against the active URL filter, returning
      # [state, parsed_body_or_nil]:
      #   :ignore  — not our operation (or the url could not be read)
      #   :pending — our operation, but the body has not arrived yet (re-read later)
      #   :seen    — our operation, already returned on an earlier drain
      #   :failed  — our operation, but unusable (no stable id, or a non-empty body
      #              that would not parse) — tallied as a capture failure
      #   :parsed  — our operation, freshly parsed (the second element is the body)
      def classify(exchange)
        url = exchange_url(exchange)
        return [:ignore, nil] unless url && yield(url)

        @observed = true
        key = exchange_key(exchange)
        if key.nil?
          # Without a stable id we cannot dedup across drains, so silently falling
          # back to a per-call object identity could re-yield duplicate pages if
          # Ferrum returns fresh wrapper objects. Count it as a capture failure
          # instead so the run records a problem rather than corrupting the walk.
          warn "[xbookmark] browser capture saw a GraphQL exchange with no stable id; counting it as a capture failure"
          @failures += 1
          return [:failed, nil]
        end
        return [:seen, nil] if @seen[key]

        body = response_body(exchange)
        # An empty body is "not ready yet", not a failure — leave it for a later
        # drain rather than permanently skipping it while the cursor advances.
        return [:pending, nil] if body.to_s.empty?

        parsed = parse(body)
        return [:failed, nil] if parsed.nil?

        @seen[key] = true
        [:parsed, parsed]
      end

      def traffic
        @page.network.traffic
      rescue StandardError => e
        # The failure tally flips a run to SessionExpired vs TransientError, so
        # surface the underlying error to make retry-vs-expired flapping debuggable
        # instead of swallowing it silently.
        warn "[xbookmark] browser capture could not read network traffic: #{e.class}: #{e.message}"
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
        exchange.id if exchange.respond_to?(:id)
      end

      def parse(body)
        JSON.parse(body)
      rescue StandardError => e
        # A non-empty body that won't parse is a genuine capture failure (corrupt
        # response or a shape change), distinct from an empty/absent body — surface
        # it so the operator can tell a parse break from an empty timeline.
        warn "[xbookmark] browser capture could not parse a GraphQL body: #{e.class}: #{e.message}"
        @failures += 1
        nil
      end

      def response_body(exchange)
        exchange.response&.body
      end
    end
  end
end
