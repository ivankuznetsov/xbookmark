# frozen_string_literal: true

require_relative "../../xbookmark"
require_relative "../x/client"
require_relative "session"
require_relative "graphql_capture"
require_relative "normalizer"
require_relative "errors"

module Xbookmark
  module Browser
    # The browser bookmark source. Implements the same duck-typed contract as
    # Xbookmark::X::Client — `bookmarks(user_id:, pagination_token:, max_results:)
    # { |envelope| }` yielding API v2 page envelopes, and `get_tweet(id)`
    # returning a single-tweet API v2 payload (raising SourceUnavailable when the
    # tweet is gone, never returning nil) — by reading X's internal GraphQL
    # responses through a real headless page and normalizing them. Drop-in for
    # the Sync::Runner, so the whole downstream pipeline runs unchanged.
    #
    # Lifecycle: the browser is built lazily and kept alive across calls (so a
    # backfill that fetches many single tweets does not cold-start Chromium per
    # tweet). The Sync::Runner calls #close once it is done with the source.
    class Source
      # Single definition lives in Session; aliased here for the public/test API.
      BOOKMARKS_URL = Session::BOOKMARKS_URL
      # Scroll the real page to make X issue the next authentic Bookmarks
      # request (no client-side request forgery).
      SCROLL_JS = "window.scrollTo(0, document.body.scrollHeight)"
      # Give a lazily-loading timeline a few empty settles before concluding the
      # history is exhausted (scaled up from 2 so a slow timeline is less likely
      # to be truncated).
      MAX_EMPTY_ROUNDS = 3
      # Hard backstop on total scroll iterations so an ever-advancing cursor or a
      # never-settling page cannot run the daily timer unbounded. 10_000 pages of
      # ~50 bookmarks each is far beyond any real timeline.
      MAX_TIMELINE_ITERATIONS = 10_000
      # The browser timeline page controls its own GraphQL page size; reuse the
      # API page size constant as the enum_for default since the Runner always
      # passes max_results explicitly anyway.
      DEFAULT_PAGE_SIZE = Xbookmark::X::Client::BOOKMARK_PAGE_SIZE

      def initialize(config:, session: nil)
        @config = config
        @session = session
      end

      # Yields API v2 page envelopes. `user_id` is ignored (the browser bookmarks
      # timeline is implicitly "my bookmarks") and `pagination_token` is accepted
      # for contract parity with X::Client but ignored (X's page drives its own
      # cursor); `max_results` is a hint only. The Runner caps total items via
      # `limit`.
      def bookmarks(user_id: nil, pagination_token: nil, max_results: DEFAULT_PAGE_SIZE, &block)
        unless block
          return enum_for(:bookmarks, user_id: user_id, pagination_token: pagination_token, max_results: max_results)
        end

        begin
          session.with_page do |page|
            page.go_to(Session::BOOKMARKS_URL)
            guard_session!(page)
            walk_timeline(page, &block)
          end
        rescue Xbookmark::Error
          # Domain errors (SessionExpired, ConfigError, the walk's transient /
          # session signals) already are the source-block contract — pass through.
          raise
        rescue StandardError => e
          # A flaky browser/CDP failure must isolate this source, not abort a
          # multi-source run; map it onto the transient source-block contract.
          raise TransientError, "browser bookmark source failed: #{e.class}: #{e.message}"
        ensure
          # Pagination is the terminal browser operation of a sync; quit here so
          # the daily run does not leave Chromium resident. Guarded to the block
          # path (the no-block enum returns above without building a session).
          session.quit
        end
      end

      # Returns a single-tweet API v2 payload ({ "data" => tweet, "includes" }),
      # matching X::Client#get_tweet. Raises SourceUnavailable when the tweet is
      # genuinely gone and TransientError when the capture itself failed — it
      # never returns nil, so the Runner can retry a transient miss instead of
      # concluding the tweet is permanently unavailable.
      def get_tweet(id)
        session.with_page do |page|
          page.go_to(tweet_url(id))
          guard_session!(page)
          settle(page)

          capture = GraphqlCapture.new(page)
          gql = capture.drain_tweets.last
          unless gql
            raise TransientError, "browser capture failed for tweet #{id}" if capture.failures?

            raise SourceUnavailable, "tweet #{id} unavailable via browser source"
          end

          envelope = Normalizer.new(gql).single_tweet_envelope(id)
          tweet = envelope["data"].first
          raise SourceUnavailable, "tweet #{id} unavailable via browser source" unless tweet

          { "data" => tweet, "includes" => envelope["includes"] }
        end
      rescue Xbookmark::Error
        raise
      rescue StandardError => e
        raise TransientError, "browser single-tweet fetch failed: #{e.class}: #{e.message}"
      end

      # Releases the browser. Idempotent; safe to call even if the source was
      # never used (no session is built just to quit it).
      def close
        @session&.quit
      end

      private

      def walk_timeline(page)
        capture = GraphqlCapture.new(page)
        seen_cursor = nil
        empty_rounds = 0
        pages = 0
        stalled = false
        normalize_failed = false

        MAX_TIMELINE_ITERATIONS.times do
          settled = settle(page)
          stalled ||= !settled
          responses = capture.drain_bookmarks

          if responses.empty?
            empty_rounds += 1
            break if empty_rounds > MAX_EMPTY_ROUNDS

            scroll(page)
            next
          end

          empty_rounds = 0
          pages += responses.size
          cursor = seen_cursor
          responses.each do |gql|
            envelope, ok = normalize_page(gql)
            normalize_failed ||= !ok
            yield envelope
            cursor = envelope.dig("meta", "next_token") || cursor
          end

          break if cursor.nil? || cursor == seen_cursor

          seen_cursor = cursor
          scroll(page)
        end

        finish_walk(pages, empty_rounds, capture, stalled, normalize_failed)
      end

      # Interpret how the walk ended. An authenticated bookmarks page always
      # issues at least one Bookmarks query (an empty list still returns an empty
      # timeline), so zero captured responses means the page never queried
      # bookmarks: a transient capture/stall (retry) or an expired/checkpointed
      # session served at the same URL (re-login). When some pages came through
      # but we stopped on empty rounds, warn that the tail may be incomplete
      # rather than silently treating a truncated timeline as exhausted.
      def finish_walk(pages, empty_rounds, capture, stalled, normalize_failed)
        if pages.zero?
          if capture.failures? || stalled
            raise TransientError, "browser bookmarks capture failed; will retry next run"
          end

          raise SessionExpired,
                "browser session expired or checkpointed; re-run `xbookmark auth login --browser`"
        end

        # A page that crashed the normalizer was dropped to an empty envelope,
        # which also drops its cursor — so the walk can stop short of true
        # end-of-history while still reporting pages>0. Surface it as transient
        # (like a capture failure) so backfill records a source error and retries
        # next run instead of marking an incomplete history complete.
        if normalize_failed
          raise TransientError,
                "browser bookmarks page failed to normalize; history tail may be incomplete, will retry next run"
        end

        # A clean settled empty-rounds stop is just end-of-history; only warn when
        # the stop is suspicious (the page stalled, or a capture failed), which is
        # the case that could silently truncate the tail of the timeline.
        return unless empty_rounds > MAX_EMPTY_ROUNDS && (stalled || capture.failures?)

        warn "[xbookmark] browser timeline walk stopped after #{MAX_EMPTY_ROUNDS} empty scroll rounds while the " \
             "page was unsettled; the bookmark history tail may be incomplete and will be retried next run."
      end

      # Normalize one captured page, isolating a malformed page to an empty
      # envelope so one bad page never aborts the walk mid-stream. Returns
      # [envelope, ok] so the walk can tell a dropped page from a real empty one
      # and refuse to treat the run as a complete backfill.
      def normalize_page(gql)
        [Normalizer.new(gql).envelope, true]
      rescue StandardError => e
        warn "[xbookmark] skipping a malformed bookmarks page: #{e.class}: #{e.message}"
        [{ "data" => [], "includes" => { "users" => [], "media" => [], "tweets" => [] }, "meta" => {} }, false]
      end

      def guard_session!(page)
        return unless Session.login_redirect?(page.current_url)

        raise SessionExpired,
              "browser session expired or checkpointed; re-run `xbookmark auth login --browser`"
      end

      # Returns true when the network settled, false when it timed out / errored.
      # A non-settle (incl. Ferrum::TimeoutError) must not masquerade as a clean
      # end-of-history; the walk tracks it so a never-settled empty walk surfaces
      # as transient rather than a silent empty sync.
      def settle(page)
        page.network.wait_for_idle
        true
      rescue StandardError
        false
      end

      def scroll(page)
        page.execute(SCROLL_JS)
      end

      def tweet_url(id)
        "https://x.com/i/web/status/#{id}"
      end

      def session
        @session ||= Session.new(config: @config, headless: true)
      end
    end
  end
end
