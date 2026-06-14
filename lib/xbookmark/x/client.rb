# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require "json"
require_relative "auth"
require_relative "expansions"

module Xbookmark
  module X
    class Client
      API_BASE = "https://api.twitter.com"
      BOOKMARK_PAGE_SIZE = 50

      EXPANSIONS = "author_id,attachments.media_keys,referenced_tweets.id"
      TWEET_FIELDS = "created_at,conversation_id,referenced_tweets,entities,attachments,author_id"
      USER_FIELDS = "username,name,profile_image_url"
      MEDIA_FIELDS = "type,url,preview_image_url,variants,duration_ms,alt_text,height,width"

      def initialize(config:, store: nil, auth: nil, conn: nil)
        @config = config
        @store = store
        @auth = auth
        @conn = conn
      end

      # Yields each page payload. If a block is not given, returns an enumerator.
      # Re-raises Xbookmark::AuthError, Xbookmark::RateLimited.
      def bookmarks(user_id:, pagination_token: nil, max_results: BOOKMARK_PAGE_SIZE)
        return enum_for(:bookmarks, user_id: user_id, pagination_token: pagination_token, max_results: max_results) unless block_given?

        params = {
          "max_results" => max_results,
          "expansions" => EXPANSIONS,
          "tweet.fields" => TWEET_FIELDS,
          "user.fields" => USER_FIELDS,
          "media.fields" => MEDIA_FIELDS
        }
        token = pagination_token
        loop do
          params["pagination_token"] = token if token
          payload = get_json("/2/users/#{user_id}/bookmarks", params)
          yield payload
          token = (payload["meta"] || {})["next_token"]
          break unless token
        end
      end

      # Fetches a single tweet (used to expand quoted/reply context).
      def get_tweet(id, expansions: EXPANSIONS)
        params = {
          "expansions" => expansions,
          "tweet.fields" => TWEET_FIELDS,
          "user.fields" => USER_FIELDS,
          "media.fields" => MEDIA_FIELDS
        }
        get_json("/2/tweets/#{id}", params, source_unavailable: true)
      end

      def conversation(id, max_results: 50)
        params = {
          "query" => "conversation_id:#{id}",
          "max_results" => max_results,
          "expansions" => EXPANSIONS,
          "tweet.fields" => TWEET_FIELDS,
          "user.fields" => USER_FIELDS,
          "media.fields" => MEDIA_FIELDS
        }
        get_json("/2/tweets/search/recent", params)
      end

      private

      def get_json(path, params, source_unavailable: false)
        ensure_token!
        res = conn.get(path, params) do |req|
          req.headers["Authorization"] = "Bearer #{@config.x_access_token}"
        end

        case res.status
        when 200..299
          JSON.parse(res.body)
        when 401
          # token may have just expired racily; refresh once then retry
          refresh_token!
          res2 = conn.get(path, params) do |req|
            req.headers["Authorization"] = "Bearer #{@config.x_access_token}"
          end
          raise AuthError, "X API auth failed (#{res2.status}): #{res2.body}" unless res2.success?
          JSON.parse(res2.body)
        when 429
          retry_after = res.headers["x-rate-limit-reset"] || res.headers["retry-after"]
          raise RateLimited.new("X API rate-limited", reset_at: retry_after)
        when 403, 404
          raise SourceUnavailable, "X source unavailable (#{res.status}): #{res.body}" if source_unavailable

          raise TransientError, "X API error #{res.status}: #{res.body}"
        else
          raise TransientError, "X API error #{res.status}: #{res.body}"
        end
      rescue Faraday::Error => e
        raise TransientError, "X API transport failed: #{e.message}"
      end

      def conn
        @conn ||= Faraday.new(url: API_BASE) do |f|
          f.request :retry, max: 2, interval: 1.0,
                    retry_statuses: [500, 502, 503, 504]
          f.adapter Faraday.default_adapter
        end
      end

      def ensure_token!
        return if @config.x_access_token && !near_expiry?
        refresh_token!
      end

      def near_expiry?
        ts = @config.x_token_expires_at
        return false unless ts
        Time.now.to_i >= (ts.to_i - 60)
      end

      def refresh_token!
        return unless @config.x_refresh_token && !@config.x_refresh_token.empty?
        result = (@auth ||= Auth.new(@config)).refresh!
        # Mutate config in-place so subsequent calls see the new token.
        @config.x_access_token = result.access_token
        @config.x_refresh_token = result.refresh_token if result.refresh_token
        @config.x_token_expires_at = result.expires_at.to_i
      end
    end
  end
end
