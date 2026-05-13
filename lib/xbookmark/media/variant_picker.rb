# frozen_string_literal: true

module Xbookmark
  module Media
    module VariantPicker
      module_function

      # Picks the highest-bitrate mp4 variant from an X video media object.
      # Returns nil if none found.
      def best_video_url(media)
        variants = (media.variants || []).select { |v| v["content_type"] == "video/mp4" }
        return nil if variants.empty?
        variants.max_by { |v| v["bit_rate"].to_i }["url"]
      end
    end
  end
end
