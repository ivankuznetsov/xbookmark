# frozen_string_literal: true

require "digest"
require "time"
require_relative "wikilinks"

module Xbookmark
  module Render
    class PathBuilder
      RESERVED = %w[con prn aux nul com1 com2 com3 com4 com5 com6 com7 com8 com9 lpt1 lpt2 lpt3 lpt4 lpt5 lpt6 lpt7 lpt8 lpt9 . ..].freeze
      HUMAN_PREFIX_BYTES = 96

      def initialize(vault_path:)
        @vault_path = vault_path
      end

      def path_for(bookmark, enrichment: nil, existing_path: nil, taken_paths: [])
        if existing_path && !existing_path.to_s.empty?
          return existing_path if existing_path.to_s.start_with?("/")

          return File.join(@vault_path, existing_path)
        end

        dir = File.join(@vault_path, "bookmarks", bookmark_date(bookmark).strftime("%Y/%m/%d"))
        filename = filename_for(bookmark, enrichment: enrichment, taken_paths: taken_paths, dir: dir)
        File.join(dir, filename)
      end

      def filename_for(bookmark, enrichment: nil, taken_paths: [], dir: nil)
        tweet_id = bookmark.tweet_id.to_s
        human = human_prefix(bookmark, enrichment)
        filename = "#{human}-#{tweet_id}.md"
        return filename unless collision?(filename, taken_paths, dir)

        "#{truncate_bytes(human, HUMAN_PREFIX_BYTES - 9)}-#{Digest::SHA256.hexdigest(tweet_id)[0, 8]}-#{tweet_id}.md"
      end

      def human_prefix(bookmark, enrichment = nil)
        author = Wikilinks.author_slug(bookmark.author_handle)
        source = [title(enrichment), summary(enrichment), bookmark.text].find { |value| !value.to_s.strip.empty? }
        slug = Wikilinks.slug([author, source].compact.join(" "))
        slug = "bookmark" if RESERVED.include?(slug) || slug.empty?
        truncate_bytes(slug, HUMAN_PREFIX_BYTES)
      end

      private

      def title(enrichment)
        enrichment.respond_to?(:title) ? enrichment.title : nil
      end

      def summary(enrichment)
        enrichment.respond_to?(:summary) ? enrichment.summary : nil
      end

      def bookmark_date(bookmark)
        Time.parse(bookmark.bookmarked_at.to_s).utc
      rescue ArgumentError
        Time.parse(bookmark.created_at.to_s).utc
      end

      def collision?(filename, taken_paths, dir)
        taken_paths.any? { |path| File.basename(path) == filename } || (dir && File.exist?(File.join(dir, filename)))
      end

      def truncate_bytes(value, max)
        out = +""
        value.each_char do |char|
          break if (out + char).bytesize > max

          out << char
        end
        out.gsub(/-+\z/, "")
      end
    end
  end
end
