# frozen_string_literal: true

require_relative "../../xbookmark"
require_relative "session"
require_relative "graphql_capture"
require_relative "normalizer"
require_relative "errors"

module Xbookmark
  module Browser
    # The browser bookmark source. Implements the same duck-typed contract as
    # Xbookmark::X::Client — `bookmarks(user_id:, max_results:) { |envelope| }`
    # yielding API v2 page envelopes, and `get_tweet(id)` returning a
    # single-tweet API v2 payload — by reading X's internal GraphQL responses
    # through a real headless page and normalizing them. Drop-in for the
    # Sync::Runner, so the whole downstream pipeline runs unchanged.
    class Source
      BOOKMARKS_URL = "https://x.com/i/bookmarks"
      # Scroll the real page to make X issue the next authentic Bookmarks
      # request (no client-side request forgery).
      SCROLL_JS = "window.scrollTo(0, document.body.scrollHeight)"
      # Give a lazily-loading timeline a couple of empty settles before
      # concluding the history is exhausted.
      MAX_EMPTY_ROUNDS = 2
      # Mirrors X::Client::BOOKMARK_PAGE_SIZE; only used as the enum_for default
      # since the Runner always passes max_results explicitly.
      DEFAULT_PAGE_SIZE = 50

      def initialize(config:, session: nil)
        @config = config
        @session = session
      end

      # user_id is ignored — the browser bookmarks timeline is implicitly
      # "my bookmarks". max_results is a hint only; X's page controls the
      # GraphQL page size, and the Runner caps total items via `limit`.
      def bookmarks(user_id: nil, max_results: DEFAULT_PAGE_SIZE, &block)
        return enum_for(:bookmarks, user_id: user_id, max_results: max_results) unless block

        session.with_page do |page|
          page.go_to(BOOKMARKS_URL)
          guard_session!(page)
          walk_timeline(page, &block)
        end
      ensure
        session.quit
      end

      # Returns a single-tweet API v2 payload ({ "data" => tweet, "includes" })
      # or nil when the tweet is unavailable, matching X::Client#get_tweet.
      def get_tweet(id)
        session.with_page do |page|
          page.go_to(tweet_url(id))
          guard_session!(page)
          settle(page)
          gql = GraphqlCapture.new(page).drain_tweets.last
          return nil unless gql

          envelope = Normalizer.new(gql).single_tweet_envelope
          tweet = envelope["data"].first
          tweet && { "data" => tweet, "includes" => envelope["includes"] }
        end
      ensure
        session.quit
      end

      private

      def walk_timeline(page)
        capture = GraphqlCapture.new(page)
        seen_cursor = nil
        empty_rounds = 0

        loop do
          settle(page)
          responses = capture.drain_bookmarks
          if responses.empty?
            empty_rounds += 1
            break if empty_rounds > MAX_EMPTY_ROUNDS

            scroll(page)
            next
          end

          empty_rounds = 0
          cursor = seen_cursor
          responses.each do |gql|
            envelope = Normalizer.new(gql).envelope
            yield envelope
            cursor = envelope.dig("meta", "next_token") || cursor
          end

          break if cursor.nil? || cursor == seen_cursor

          seen_cursor = cursor
          scroll(page)
        end
      end

      def guard_session!(page)
        return unless Session.login_redirect?(page.current_url)

        raise SessionExpired,
              "browser session expired or checkpointed; re-run `xbookmark auth login --browser`"
      end

      def settle(page)
        page.network.wait_for_idle
      rescue StandardError
        nil
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
