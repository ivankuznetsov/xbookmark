# frozen_string_literal: true

module Xbookmark
  module X
    Media = Struct.new(:media_key, :type, :url, :preview_image_url, :alt_text,
                       :variants, :duration_ms, :width, :height, keyword_init: true) do
      def video?
        type == "video" || type == "animated_gif"
      end

      def image?
        type == "photo"
      end
    end

    Bookmark = Struct.new(
      :tweet_id,
      :author_id,
      :author_handle,
      :author_name,
      :author_profile_image,
      :created_at,
      :text,
      :media,
      :quoted_tweet_id,
      :quoted_tweet,
      :in_reply_to_tweet_id,
      :conversation_id,
      :urls,
      :bookmarked_at,
      :raw,
      keyword_init: true
    ) do
      def url
        return nil unless author_handle && tweet_id
        "https://x.com/#{author_handle}/status/#{tweet_id}"
      end
    end
  end
end
