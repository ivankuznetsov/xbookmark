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
        # X's internal GraphQL is an undocumented, hostile surface: a tombstone,
        # ad slot, or shape change can hand us anything. Treat a non-Hash payload
        # as empty so a single bad response degrades to an empty page rather than
        # crashing the whole run.
        @payload = graphql_payload.is_a?(Hash) ? graphql_payload : {}
      end

      # The canonical empty API v2 page envelope. Callers that must emit an empty
      # page (e.g. the Source dropping a malformed page) route through here so the
      # envelope shape has a single author and cannot drift from #build_envelope.
      def self.empty_envelope
        new(nil).envelope
      end

      # Normalizes a full bookmark timeline page → API v2 page envelope.
      def envelope
        includes = new_includes
        data = timeline_entries.filter_map { |entry| normalize_tweet_entry(entry, includes) }
        build_envelope(data, next_token: bottom_cursor, includes: includes)
      end

      # Normalizes a single TweetDetail/TweetResultByRestId result → a
      # single-tweet API v2 envelope (for get_tweet/retry/resync parity).
      # `requested_id` selects the focal tweet out of a TweetDetail thread so a
      # reply resyncs itself rather than the thread root that precedes it.
      def single_tweet_envelope(requested_id = nil)
        includes = new_includes
        result = single_tweet_result(requested_id)
        tweet = result && normalize_tweet_result(result, includes)
        build_envelope([tweet].compact, next_token: nil, includes: includes)
      end

      private

      # Per-call includes accumulators. Kept method-local (threaded through the
      # registration helpers) so includes can never leak across calls and no
      # public entry point has to remember to reset shared instance state first.
      def new_includes
        { users: {}, media: {}, tweets: {} }
      end

      def build_envelope(data, next_token:, includes:)
        meta = {}
        meta["next_token"] = next_token if next_token
        {
          "data" => data,
          "includes" => {
            "users" => includes[:users].values,
            "media" => includes[:media].values,
            "tweets" => includes[:tweets].values
          },
          "meta" => meta
        }
      end

      def timeline_entries
        # Every array element is assumed to be a Hash below; X can return
        # non-Hash slots, so filter defensively before indexing into them.
        instructions = Array(dig_timeline&.dig("instructions")).select { |ins| ins.is_a?(Hash) }
        add = instructions.find { |ins| ins["type"] == "TimelineAddEntries" } || {}
        Array(add["entries"]).select { |entry| entry.is_a?(Hash) }
      end

      def dig_timeline
        timeline = @payload.dig("data", "bookmark_timeline_v2", "timeline")
        # Defensive fallback to the legacy bookmark_timeline key; not exercised by
        # the committed fixtures (only by an inline test payload).
        timeline ||= @payload.dig("data", "bookmark_timeline", "timeline")
        timeline if timeline.is_a?(Hash)
      rescue TypeError
        # A hostile `data` shape (e.g. an Array) makes #dig raise; treat as empty.
        nil
      end

      def bottom_cursor
        cursor_entry = timeline_entries.reverse_each.find do |entry|
          content = entry["content"] || {}
          content["entryType"] == "TimelineTimelineCursor" && content["cursorType"] == "Bottom"
        end
        cursor_entry&.dig("content", "value")
      end

      def normalize_tweet_entry(entry, includes)
        content = entry["content"]
        return nil unless content.is_a?(Hash) && content["entryType"] == "TimelineTimelineItem"

        item = content["itemContent"]
        return nil unless item.is_a?(Hash) && item["itemType"] == "TimelineTweet"

        result = item.dig("tweet_results", "result")
        result && normalize_tweet_result(result, includes)
      end

      # Returns the API v2 tweet hash and registers the author, media, and any
      # quoted tweet into includes. Also resolves the inner tweet of a
      # visibility wrapper.
      def normalize_tweet_result(result, includes)
        return nil unless result.is_a?(Hash)

        tweet = unwrap(result)
        return nil unless tweet.is_a?(Hash)

        legacy = tweet["legacy"]
        legacy = {} unless legacy.is_a?(Hash)
        id = tweet["rest_id"] || legacy["id_str"]
        return nil unless id

        register_user(tweet, includes)
        media_keys = register_media(legacy, includes)
        quoted_id = register_quoted(tweet, legacy, includes)

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

      def register_user(tweet, includes)
        user = tweet.dig("core", "user_results", "result")
        return unless user

        rest_id = user["rest_id"]
        return unless rest_id

        legacy = user["legacy"] || {}
        core = user["core"] || {}
        includes[:users][rest_id] ||= {
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

      def register_quoted(tweet, legacy, includes)
        quoted_result = tweet.dig("quoted_status_result", "result")
        quoted_id = legacy["quoted_status_id_str"]

        if quoted_result
          quoted_tweet = normalize_tweet_result(quoted_result, includes)
          if quoted_tweet
            quoted_id ||= quoted_tweet["id"]
            includes[:tweets][quoted_tweet["id"]] ||= quoted_tweet
          end
        end
        quoted_id
      end

      def entity_urls(legacy)
        urls = legacy.dig("entities", "urls") || []
        Array(urls).select { |u| u.is_a?(Hash) }.map do |u|
          {
            "url" => u["url"],
            "expanded_url" => u["expanded_url"],
            "display_url" => u["display_url"]
          }.compact
        end
      end

      def register_media(legacy, includes)
        media = legacy.dig("extended_entities", "media")
        media = legacy.dig("entities", "media") if media.nil? || media.empty?
        Array(media).filter_map do |m|
          next unless m.is_a?(Hash)

          key = m["media_key"]
          next unless key

          includes[:media][key] ||= normalize_media(m)
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

        Array(variants).select { |v| v.is_a?(Hash) }.map do |v|
          {
            "bit_rate" => v["bitrate"],
            "content_type" => v["content_type"],
            "url" => v["url"]
          }.compact
        end
      end

      def single_tweet_result(requested_id = nil)
        # TweetResultByRestId shape — X already returns exactly the asked-for tweet.
        by_rest_id = @payload.dig("data", "tweetResult", "result")
        return by_rest_id if by_rest_id

        # TweetDetail timeline shape: the threaded conversation carries several
        # tweets (thread root, the focal tweet, replies). Select the one whose
        # rest_id matches the requested id so resyncing a reply returns that
        # reply, not whichever TimelineTweet happens to come first. Fall back to
        # the first only when no id was requested (callers that just want any).
        results = tweet_detail_results
        return results.first if requested_id.nil?

        results.find { |result| tweet_result_id(result) == requested_id.to_s }
      end

      # All TimelineTweet results from a TweetDetail threaded conversation, in
      # page order.
      def tweet_detail_results
        instructions = Array(@payload.dig("data", "threaded_conversation_with_injections_v2", "instructions"))
                       .select { |ins| ins.is_a?(Hash) }
        add = instructions.find { |ins| ins["type"] == "TimelineAddEntries" } || {}
        Array(add["entries"]).select { |e| e.is_a?(Hash) }.filter_map do |e|
          next unless e.dig("content", "itemContent", "itemType") == "TimelineTweet"

          e.dig("content", "itemContent", "tweet_results", "result")
        end
      end

      # The rest_id of a tweet result, unwrapping a visibility wrapper, using the
      # same id resolution as #normalize_tweet_result so matching is consistent.
      def tweet_result_id(result)
        tweet = unwrap(result)
        return nil unless tweet.is_a?(Hash)

        (tweet["rest_id"] || tweet.dig("legacy", "id_str"))&.to_s
      end

      def iso8601(created_at)
        return nil if created_at.nil?
        # X GraphQL uses the classic "Wed Feb 12 20:00:00 +0000 2025" format;
        # convert to millisecond-precision ISO8601 so frontmatter dates match the
        # API v2 path exactly (API v2 emits e.g. "2026-01-01T00:00:00.000Z").
        Time.parse(created_at).utc.iso8601(3)
      rescue ArgumentError, TypeError => e
        # ArgumentError: an unparseable string. TypeError: a non-String value
        # (e.g. X handing back an Integer epoch). Emitting it verbatim would flow
        # to PathBuilder#bookmark_date, which re-parses the same bad value and
        # re-raises — marking the bookmark a permanent error and dropping it
        # forever. Drop the field instead (it is .compact'd, so simply omitted),
        # and warn so the swallow is observable.
        warn "[xbookmark] dropping unparseable created_at #{created_at.inspect}: #{e.class}: #{e.message}"
        nil
      end
    end
  end
end
