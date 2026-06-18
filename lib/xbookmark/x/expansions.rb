# frozen_string_literal: true

require_relative "bookmark"

module Xbookmark
  module X
    # Parses the X API v2 expansions/includes payload into rich Bookmark objects.
    class Expansions
      def initialize(payload)
        @payload = payload
        includes = payload["includes"] || {}
        @users    = index_by(includes["users"] || [], "id")
        @media    = index_by(includes["media"] || [], "media_key")
        @tweets   = index_by(includes["tweets"] || [], "id")
      end

      def bookmarks
        (@payload["data"] || []).map { |t| build_bookmark(t) }
      end

      def next_token
        (@payload["meta"] || {})["next_token"]
      end

      private

      def index_by(arr, key)
        arr.each_with_object({}) { |row, acc| acc[row[key]] = row }
      end

      def build_bookmark(t)
        author = @users[t["author_id"]] || {}
        media_keys = (t.dig("attachments", "media_keys") || [])
        media_objs = media_keys.map { |k| @media[k] }.compact.map { |m| build_media(m) }

        referenced = t["referenced_tweets"] || []
        quoted_id = referenced.find { |r| r["type"] == "quoted" }&.dig("id")
        replied_id = referenced.find { |r| r["type"] == "replied_to" }&.dig("id")

        Bookmark.new(
          tweet_id: t["id"],
          author_id: t["author_id"],
          author_handle: author["username"],
          author_name: author["name"],
          author_profile_image: author["profile_image_url"],
          created_at: t["created_at"],
          text: t["text"],
          media: media_objs,
          quoted_tweet_id: quoted_id,
          quoted_tweet: quoted_id && @tweets[quoted_id],
          in_reply_to_tweet_id: replied_id,
          conversation_id: t["conversation_id"],
          urls: extract_urls(t),
          # NOTE: X's bookmarks endpoint does not expose a true bookmark
          # timestamp — only the tweet's `created_at` is available. We
          # copy it into `bookmarked_at` so downstream code (e.g. the
          # YYYY/MM/DD bookmark wiki sharding in PathBuilder#bookmark_date)
          # has a stable date, but it is the *tweet creation* date, not
          # the date the user actually bookmarked it.
          bookmarked_at: t["created_at"],
          raw: t
        )
      end

      def build_media(m)
        Media.new(
          media_key: m["media_key"],
          type: m["type"],
          url: m["url"],
          preview_image_url: m["preview_image_url"],
          alt_text: m["alt_text"],
          variants: m["variants"] || [],
          duration_ms: m["duration_ms"],
          width: m["width"],
          height: m["height"]
        )
      end

      def extract_urls(t)
        urls = (t.dig("entities", "urls") || [])
        urls.map { |u| { url: u["url"], expanded_url: u["expanded_url"], display_url: u["display_url"], title: u["title"] } }
      end
    end
  end
end
