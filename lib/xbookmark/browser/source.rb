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
    # tweet). #bookmarks is the terminal sync operation — it quits the session in
    # its own `ensure`, so a daily run never leaves Chromium resident — and the
    # Sync::Runner calls #close (an idempotent backstop that also covers the
    # resync/get_tweet-only path) once it is done with the source.
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
        raise ArgumentError, "config required" if config.nil?

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
          settled = settle(page)

          capture = GraphqlCapture.new(page)
          gql = capture.drain_tweets.last
          unless gql
            # A captured tweet is returned even when the settle stalled (the body
            # was already drained), but with nothing captured a stalled/failed
            # load is transient — reserve the permanent SourceUnavailable for a
            # clean settle that simply produced no tweet.
            raise TransientError, "browser capture failed for tweet #{id}" if capture.failures? || !settled

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
        # Track every cursor we've advanced through, not just the last one: a
        # cursor *cycle* of period > 1 (c1,c2,c1,c2,…) would defeat a single-slot
        # check and re-yield duplicate pages until the iteration cap, burning the
        # whole RuntimeMaxSec window. Break on any repeat instead.
        seen_cursors = {}
        empty_rounds = 0
        pages = 0
        stalled = false
        normalize_failed = false
        missing_cursor = false

        # The loop returns the iteration count on natural completion and nil when
        # any `break` fires, so a walk that exhausts the cap while still advancing
        # is distinguishable from one that stopped on a real terminal condition.
        completed = MAX_TIMELINE_ITERATIONS.times do
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
          page_cursor = nil
          responses.each do |gql|
            envelope, ok = normalize_page(gql)
            normalize_failed ||= !ok
            yield envelope
            page_cursor = envelope.dig("meta", "next_token") || page_cursor
          end

          # A data-bearing page that exposed no Bottom cursor cannot be advanced
          # and is not a trustworthy end-of-history (X always emits a Bottom
          # cursor, even on the last page where it merely repeats) — flag it so
          # the walk surfaces a transient stop rather than sealing a possibly
          # truncated backfill as complete.
          if page_cursor.nil?
            missing_cursor = true
            break
          end

          break if seen_cursors.key?(page_cursor)

          seen_cursors[page_cursor] = true
          scroll(page)
        end

        # The initial guard only sees the session state at the start of the walk.
        # A session that expires *mid-walk* (X stops issuing Bookmarks requests and
        # serves a login/checkpoint redirect at the same URL) drains empty and
        # breaks cleanly with pages>0, which finish_walk would otherwise read as a
        # genuine end-of-history and seal a truncated backfill. Re-check the page
        # URL here so a redirect that appeared after the initial guard is
        # reclassified as SessionExpired (re-login) rather than silently dropping
        # the unfetched tail.
        guard_session!(page)

        finish_walk(pages: pages, empty_rounds: empty_rounds, capture: capture, stalled: stalled,
                    normalize_failed: normalize_failed, missing_cursor: missing_cursor,
                    hit_iteration_cap: !completed.nil?)
      end

      # Interpret how the walk ended. An authenticated bookmarks page always
      # issues at least one Bookmarks query (an empty list still returns an empty
      # timeline), so zero captured responses means the page never queried
      # bookmarks: a transient capture/stall (retry), a Bookmarks request that was
      # observed but never filled (retry), or an expired/checkpointed session
      # served at the same URL with no Bookmarks query at all (re-login). Any
      # suspicious stop after at least one page is surfaced as transient so a
      # backfill records a source error and retries instead of sealing a possibly
      # truncated history as complete.
      def finish_walk(pages:, empty_rounds:, capture:, stalled:, normalize_failed:, missing_cursor:, hit_iteration_cap:)
        if pages.zero?
          if capture.failures? || stalled || capture.observed?
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

        # A data-bearing page that exposed no pagination cursor is an untrustworthy
        # end-of-history; retry rather than seal a possibly truncated backfill.
        if missing_cursor
          raise TransientError,
                "browser bookmarks page yielded items but exposed no pagination cursor; " \
                "history tail may be incomplete, will retry next run"
        end

        # Ran out of the iteration budget while the cursor was still advancing —
        # practically unreachable, but mirror the other guards so the backstop is
        # belt-and-suspenders rather than silently sealing a truncated backfill.
        if hit_iteration_cap
          raise TransientError,
                "browser timeline walk hit the #{MAX_TIMELINE_ITERATIONS}-iteration cap before " \
                "reaching end-of-history; will retry next run"
        end

        # A clean settled empty-rounds stop is just end-of-history; only the
        # suspicious stop (the page stalled, or a capture failed) could silently
        # truncate the tail — surface it as transient so the run records a source
        # error and retries rather than sealing the backfill as complete.
        return unless empty_rounds > MAX_EMPTY_ROUNDS && (stalled || capture.failures?)

        raise TransientError,
              "browser timeline walk stopped after #{empty_rounds} empty scroll rounds while the page was " \
              "unsettled or a capture failed; the bookmark history tail may be incomplete, will retry next run"
      end

      # Normalize one captured page, isolating a malformed page to an empty
      # envelope so one bad page never aborts the walk mid-stream. Returns
      # [envelope, ok] so the walk can tell a dropped page from a real empty one
      # and refuse to treat the run as a complete backfill.
      def normalize_page(gql)
        [Normalizer.new(gql).envelope, true]
      rescue StandardError => e
        warn "[xbookmark] skipping a malformed bookmarks page: #{e.class}: #{e.message}"
        [Normalizer.empty_envelope, false]
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
