# frozen_string_literal: true

require "json"
require_relative "../render/wikilinks"

module Xbookmark
  module Sync
    class ThreadIndex
      def initialize(store: nil, bookmarks: [])
        @conversation_counts = Hash.new(0)
        Array(bookmarks).each { |bookmark| add_bookmark(bookmark) }
        Array(store&.bookmarks).each { |row| add_row(row) }
        Array(store&.pages("thread")).each { |row| @conversation_counts[row[:slug].to_s] += 2 }
      end

      def thread_for(bookmark)
        conversation = bookmark.conversation_id.to_s
        return nil if conversation.empty?
        return nil if singleton?(bookmark)

        slug = readable_slug(bookmark, conversation)
        { slug: slug, target: "threads/#{slug}", label: "thread #{slug}" }
      end

      def real_thread?(bookmark)
        !thread_for(bookmark).nil?
      end

      private

      def add_bookmark(bookmark)
        conversation = bookmark.conversation_id.to_s
        @conversation_counts[conversation] += 1 unless conversation.empty?
      end

      def add_row(row)
        payload = row[:payload_json].to_s.empty? ? nil : JSON.parse(row[:payload_json])
        data = Array(payload && payload["data"]).first || {}
        conversation = data["conversation_id"] || row[:tweet_id]
        @conversation_counts[conversation.to_s] += 1 unless conversation.to_s.empty?
      rescue JSON::ParserError
        @conversation_counts[row[:tweet_id].to_s] += 1
      end

      def singleton?(bookmark)
        conversation = bookmark.conversation_id.to_s
        @conversation_counts[conversation] < 2 && conversation == bookmark.tweet_id.to_s
      end

      def readable_slug(bookmark, conversation)
        base = Xbookmark::Render::Wikilinks.slug([bookmark.author_handle, conversation].compact.join(" "))
        base == conversation ? "thread-#{conversation}" : "#{base}-thread"
      end
    end
  end
end
