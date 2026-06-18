# frozen_string_literal: true

require_relative "../../xbookmark"
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
    #
    # #get_tweet deliberately has no per-call `ensure`: it reuses the live
    # session, so the single quit is the Runner's `ensure → close_sources` after
    # the run. That backstop covers a clean exit and any raised error; it does
    # NOT cover a SIGKILL or a bare `exit` taken *outside* `Runner#run` (a manual
    # `irb` driver, or a non-systemd scheduler with no RuntimeMaxSec hard-kill),
    # which can orphan Chromium holding the profile lock. The shipped systemd
    # unit's RuntimeMaxSec reaps such an orphan; a non-systemd entry point that
    # drives get_tweet directly must call #close itself.
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
      # Wall-clock backstop on the whole timeline walk. The iteration cap bounds
      # the number of scrolls, but each settle can block up to Ferrum's ~60s idle
      # timeout, so a repeatedly-timing-out-but-cursor-advancing walk could sit
      # for hours. The scheduled path is hard-killed at systemd
      # RuntimeMaxSec=7200, but the walk is only the *first* phase of a run — the
      # per-bookmark enrichment and the destructive taxonomy maintenance still
      # have to finish before SIGTERM. Budget the walk at a fraction of that hard
      # deadline so a slow-but-advancing timeline leaves headroom for the rest of
      # the run instead of consuming the whole window and being killed mid-work.
      MAX_WALK_SECONDS = 3600
      # The browser timeline page controls its own GraphQL page size; this is only
      # the enum_for default the Runner always overrides with an explicit
      # max_results, so inline the literal rather than coupling this independent
      # source to the API client's load graph just to read one integer.
      DEFAULT_PAGE_SIZE = 50

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
            page.go_to(BOOKMARKS_URL)
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
          tweets = capture.drain_tweets
          if tweets.empty?
            # The initial guard only saw the session state at navigation time. A
            # session that expires *after* go_to (X completes a login/checkpoint
            # redirect while the page settles) captures no tweet and can settle
            # cleanly — which would otherwise fall through to the permanent
            # SourceUnavailable below and let a retry/resync mark the row gone
            # instead of firing SESSION_EXPIRED. Re-check the settled URL so a
            # redirect that appeared after the initial guard is reclassified as
            # SessionExpired (re-login) rather than an unavailable tweet.
            guard_session!(page)

            # A captured tweet is returned even when the settle stalled (the body
            # was already drained), but with nothing captured a stalled, failed,
            # or still-pending load is transient — reserve the permanent
            # SourceUnavailable for a clean settle that simply produced no tweet. A
            # pending focal request (the TweetDetail/TweetResultByRestId was
            # observed but its body never filled) is a retryable miss, not a gone
            # tweet — mirror finish_walk, which already honors pending? on the
            # backfill path.
            raise TransientError, "browser capture failed for tweet #{id}" if capture.failures? || capture.pending? || !settled

            raise SourceUnavailable, "tweet #{id} unavailable via browser source"
          end

          # The page can fire extra TweetResultByRestId/TweetDetail calls for
          # quoted, hovercard, or recommended tweets, so the last drained response
          # is not necessarily the asked-for tweet. Select the response whose
          # normalized id matches the requested id — returning whichever drained
          # last could cache or render a stray tweet under the wrong tweet_id.
          envelope = matching_tweet_envelope(tweets, id)
          unless envelope
            # A non-empty capture that nonetheless lacks the requested id happens
            # when the focal TweetDetail/TweetResultByRestId timed out (or its body
            # never filled) and only a stray quoted/hovercard tweet drained. That is
            # a transient miss when the settle stalled, a capture failed, or the
            # focal request is still pending — mirror the empty-capture branch so the
            # Runner retries rather than recording a still-existing tweet as
            # permanently gone.
            raise TransientError, "browser capture for tweet #{id} did not include it" if capture.failures? || capture.pending? || !settled

            raise SourceUnavailable, "tweet #{id} unavailable via browser source"
          end

          { "data" => envelope["data"].first, "includes" => envelope["includes"] }
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
        # How the walk left the loop. A repeated Bottom cursor is X's strong
        # end-of-history signal, distinct from running dry on empty scroll rounds;
        # finish_walk uses this to skip the pending? check at a cursor-repeat stop
        # (a tail-end prefetch X fired and abandoned must not block sealing there).
        cursor_repeated = false

        # The loop returns the iteration count on natural completion and nil when
        # any `break` fires, so a walk that exhausts the cap while still advancing
        # is distinguishable from one that stopped on a real terminal condition.
        deadline = monotonic_now + MAX_WALK_SECONDS
        completed = MAX_TIMELINE_ITERATIONS.times do
          # Wall-clock backstop: each settle can block up to Ferrum's idle
          # timeout, so the iteration cap alone does not bound elapsed time.
          # Surface a transient stop so backfill retries rather than sitting for
          # hours on a manual run that systemd's RuntimeMaxSec does not cover.
          if monotonic_now > deadline
            raise TransientError,
                  "browser timeline walk exceeded its #{MAX_WALK_SECONDS}s wall-clock budget before " \
                  "reaching end-of-history; will retry next run"
          end

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
            cursor = envelope.dig("meta", "next_token")

            # A page that crashed the normalizer (dropped to an empty envelope,
            # losing its cursor) or a data-bearing page X served with no Bottom
            # cursor is an untrustworthy end-of-history — X always emits a Bottom
            # cursor, even on the last page where it merely repeats. Surface the
            # transient stop *before* yielding the page: a consumer that breaks on
            # the resulting cursorless envelope (the Runner's `break unless
            # next_token`) would otherwise unwind past the post-loop finish_walk
            # guard and silently seal a truncated backfill. The unfetched tail is
            # re-walked from the top next run, so nothing is permanently lost.
            unless ok
              raise TransientError,
                    "browser bookmarks page failed to normalize; history tail may be incomplete, will retry next run"
            end
            if cursor.nil?
              raise TransientError,
                    "browser bookmarks page yielded items but exposed no pagination cursor; " \
                    "history tail may be incomplete, will retry next run"
            end

            yield envelope
            page_cursor = cursor
          end

          if seen_cursors.key?(page_cursor)
            cursor_repeated = true
            break
          end

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
                    hit_iteration_cap: !completed.nil?, cursor_repeated: cursor_repeated)
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
      def finish_walk(pages:, empty_rounds:, capture:, stalled:, hit_iteration_cap:, cursor_repeated:)
        if pages.zero?
          if capture.failures? || stalled || capture.observed?
            raise TransientError, "browser bookmarks capture failed; will retry next run"
          end

          raise SessionExpired,
                "browser session expired or checkpointed; re-run `xbookmark auth login --browser`"
        end

        # The normalize-failed and missing-cursor stops are surfaced in-loop
        # (before the offending page is yielded) so a consumer break cannot bypass
        # them — see #walk_timeline.

        # Ran out of the iteration budget while the cursor was still advancing —
        # practically unreachable, but mirror the other guards so the backstop is
        # belt-and-suspenders rather than silently sealing a truncated backfill.
        if hit_iteration_cap
          raise TransientError,
                "browser timeline walk hit the #{MAX_TIMELINE_ITERATIONS}-iteration cap before " \
                "reaching end-of-history; will retry next run"
        end

        # A next-page Bookmarks request was observed after the good pages but its
        # body never filled (canceled/pending), so the drains went empty while the
        # page settled cleanly and no capture was tallied as a failure. The
        # empty-rounds guard below would otherwise read this as end-of-history and
        # seal a truncated backfill; surface it as transient so the unfetched tail
        # is retried. (The pages.zero? branch already covers this via observed?.)
        #
        # Skip this only when the walk stopped on a repeated Bottom cursor: that
        # is X's explicit end-of-history, and X commonly prefetches one more
        # Bookmarks request as the final page drains, then abandons it — leaving
        # @pending set on a history that is genuinely complete. Honoring pending?
        # there would keep a finished full backfill from ever sealing.
        if !cursor_repeated && capture.pending?
          raise TransientError,
                "browser bookmarks next page was observed but never filled; " \
                "history tail may be incomplete, will retry next run"
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

      # Selects the captured single-tweet response that actually carries the
      # requested id. Scans newest-first so the freshest matching capture wins,
      # and only returns an envelope whose tweet id equals the requested id — a
      # stray response for a quoted/hovercard/recommended tweet that happened to
      # drain last must never be cached or rendered under the requested tweet_id.
      def matching_tweet_envelope(gql_responses, id)
        gql_responses.reverse_each do |gql|
          envelope = Normalizer.new(gql).single_tweet_envelope(id)
          tweet = envelope["data"].first
          return envelope if tweet && tweet["id"] == id.to_s
        end
        nil
      end

      # Monotonic seconds for the walk's wall-clock deadline. Wrapped so the
      # backstop is testable without stubbing a global clock.
      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
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
