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

        slug = readable_slug(conversation)
        { slug: slug, target: "threads/#{slug}", label: "thread #{slug}" }
      end

      def real_thread?(bookmark)
        !thread_for(bookmark).nil?
      end

      def add_bookmark(bookmark)
        conversation = bookmark.conversation_id.to_s
        @conversation_counts[conversation] += 1 unless conversation.empty?
      end

      def add_bookmarks(bookmarks)
        Array(bookmarks).each { |bookmark| add_bookmark(bookmark) }
      end

      private

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

      # Thread page names are derived from the conversation id alone, so every
      # bookmark in a conversation (even across different authors) resolves to
      # the same thread page. The "thread" prefix also guarantees a
      # non-numeric basename, so a real thread is never mistaken for a legacy
      # numeric singleton during a rebuild prune.
      def readable_slug(conversation)
        name = Xbookmark::Render::Wikilinks.slug(conversation)
        name.start_with?("thread") ? name : "thread-#{name}"
      end
    end
  end
end
