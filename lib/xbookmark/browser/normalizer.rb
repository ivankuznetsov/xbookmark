# frozen_string_literal: true

require "time"

module Xbookmark
  module Browser
    # Pure transform from X's internal GraphQL `Bookmarks` response into the
    # exact API v2 envelope `Xbookmark::X::Expansions` consumes:
    #
    #   { "data" => [...tweets...],
    #     "includes" => { "users" => [...], "media" => [...], "tweets" => [...] },
    #     "meta" => { "next_token" => <bottom cursor> } }
    #
    # Achieving envelope parity here is what gives the browser source full
    # downstream fidelity (media variants, quoted tweets, conversation_id,
    # entity urls, author handle/name) with zero changes to the pipeline,
    # renderer, downloader, whisper, or enrichment code.
    class Normalizer
      def initialize(graphql_payload)
        @payload = graphql_payload || {}
        @users = {}
        @media = {}
        @tweets = {}
      end

      # Normalizes a full bookmark timeline page → API v2 page envelope.
      def envelope
        reset_includes!
        data = timeline_entries.filter_map { |entry| normalize_tweet_entry(entry) }
        build_envelope(data, next_token: bottom_cursor)
      end

      # Normalizes a single TweetDetail/TweetResultByRestId result → a
      # single-tweet API v2 envelope (for get_tweet/retry/resync parity).
      def single_tweet_envelope
        reset_includes!
        result = single_tweet_result
        tweet = result && normalize_tweet_result(result)
        build_envelope([tweet].compact, next_token: nil)
      end

      private

      def reset_includes!
        @users = {}
        @media = {}
        @tweets = {}
      end

      def build_envelope(data, next_token:)
        meta = {}
        meta["next_token"] = next_token if next_token
        {
          "data" => data,
          "includes" => {
            "users" => @users.values,
            "media" => @media.values,
            "tweets" => @tweets.values
          },
          "meta" => meta
        }
      end

      def timeline_entries
        instructions = dig_timeline&.dig("instructions") || []
        add = instructions.find { |ins| ins["type"] == "TimelineAddEntries" } || {}
        Array(add["entries"])
      end

      def dig_timeline
        timeline = @payload.dig("data", "bookmark_timeline_v2", "timeline")
        # Older/alternate operation key.
        timeline ||= @payload.dig("data", "bookmark_timeline", "timeline")
        timeline
      end

      def bottom_cursor
        cursor_entry = timeline_entries.reverse_each.find do |entry|
          content = entry["content"] || {}
          content["entryType"] == "TimelineTimelineCursor" && content["cursorType"] == "Bottom"
        end
        cursor_entry&.dig("content", "value")
      end

      def normalize_tweet_entry(entry)
        content = entry["content"] || {}
        return nil unless content["entryType"] == "TimelineTimelineItem"

        item = content["itemContent"] || {}
        return nil unless item["itemType"] == "TimelineTweet"

        result = item.dig("tweet_results", "result")
        result && normalize_tweet_result(result)
      end

      # Returns the API v2 tweet hash and registers the author, media, and any
      # quoted tweet into includes. Also resolves the inner tweet of a
      # visibility wrapper.
      def normalize_tweet_result(result)
        tweet = unwrap(result)
        return nil unless tweet

        legacy = tweet["legacy"] || {}
        id = tweet["rest_id"] || legacy["id_str"]
        return nil unless id

        register_user(tweet)
        media_keys = register_media(legacy)
        quoted_id = register_quoted(tweet, legacy)

        {
          "id" => id.to_s,
          "author_id" => author_id(tweet),
          "created_at" => iso8601(legacy["created_at"]),
          "text" => full_text(tweet, legacy),
          "conversation_id" => legacy["conversation_id_str"],
          "referenced_tweets" => referenced_tweets(legacy, quoted_id),
          "entities" => { "urls" => entity_urls(legacy) },
          "attachments" => { "media_keys" => media_keys }
        }.compact
      end

      # X wraps some tweets in TweetWithVisibilityResults { tweet: {...} }.
      def unwrap(result)
        return result["tweet"] if result["__typename"] == "TweetWithVisibilityResults"
        result
      end

      def author_id(tweet)
        tweet.dig("core", "user_results", "result", "rest_id") || tweet.dig("legacy", "user_id_str")
      end

      def register_user(tweet)
        user = tweet.dig("core", "user_results", "result")
        return unless user

        rest_id = user["rest_id"]
        return unless rest_id

        legacy = user["legacy"] || {}
        core = user["core"] || {}
        @users[rest_id] ||= {
          "id" => rest_id.to_s,
          "username" => core["screen_name"] || legacy["screen_name"],
          "name" => core["name"] || legacy["name"],
          "profile_image_url" => legacy["profile_image_url_https"] || user.dig("avatar", "image_url")
        }.compact
      end

      def full_text(tweet, legacy)
        note = tweet.dig("note_tweet", "note_tweet_results", "result", "text")
        note || legacy["full_text"] || legacy["text"]
      end

      def referenced_tweets(legacy, quoted_id)
        refs = []
        replied = legacy["in_reply_to_status_id_str"]
        refs << { "type" => "replied_to", "id" => replied.to_s } if replied
        refs << { "type" => "quoted", "id" => quoted_id.to_s } if quoted_id
        refs
      end

      def register_quoted(tweet, legacy)
        quoted_result = tweet.dig("quoted_status_result", "result")
        quoted_id = legacy["quoted_status_id_str"]

        if quoted_result
          quoted_tweet = normalize_tweet_result(quoted_result)
          if quoted_tweet
            quoted_id ||= quoted_tweet["id"]
            @tweets[quoted_tweet["id"]] ||= quoted_tweet
          end
        end
        quoted_id
      end

      def entity_urls(legacy)
        urls = legacy.dig("entities", "urls") || []
        urls.map do |u|
          {
            "url" => u["url"],
            "expanded_url" => u["expanded_url"],
            "display_url" => u["display_url"]
          }.compact
        end
      end

      def register_media(legacy)
        media = legacy.dig("extended_entities", "media")
        media = legacy.dig("entities", "media") if media.nil? || media.empty?
        Array(media).filter_map do |m|
          key = m["media_key"]
          next unless key

          @media[key] ||= normalize_media(m)
          key
        end
      end

      def normalize_media(m)
        type = m["type"]
        info = m["original_info"] || {}
        {
          "media_key" => m["media_key"],
          "type" => type,
          "url" => (m["media_url_https"] if type == "photo"),
          "preview_image_url" => (m["media_url_https"] unless type == "photo"),
          "variants" => video_variants(m),
          "duration_ms" => m.dig("video_info", "duration_millis"),
          "alt_text" => m["ext_alt_text"],
          "width" => info["width"],
          "height" => info["height"]
        }.compact
      end

      def video_variants(media)
        variants = media.dig("video_info", "variants")
        return nil unless variants

        variants.map do |v|
          {
            "bit_rate" => v["bitrate"],
            "content_type" => v["content_type"],
            "url" => v["url"]
          }.compact
        end
      end

      def single_tweet_result
        # TweetResultByRestId shape.
        by_rest_id = @payload.dig("data", "tweetResult", "result")
        return by_rest_id if by_rest_id

        # TweetDetail timeline shape: dig the first TimelineTweet entry.
        instructions = @payload.dig("data", "threaded_conversation_with_injections_v2", "instructions") || []
        add = instructions.find { |ins| ins["type"] == "TimelineAddEntries" } || {}
        entry = Array(add["entries"]).find do |e|
          e.dig("content", "itemContent", "itemType") == "TimelineTweet"
        end
        entry&.dig("content", "itemContent", "tweet_results", "result")
      end

      def iso8601(created_at)
        return nil if created_at.nil?
        # X GraphQL uses the classic "Wed Feb 12 20:00:00 +0000 2025" format;
        # convert to ISO8601 so frontmatter dates match the API v2 path exactly.
        Time.parse(created_at).utc.iso8601
      rescue ArgumentError
        created_at
      end
    end
  end
end
