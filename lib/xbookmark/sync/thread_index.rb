# frozen_string_literal: true

require "json"
require_relative "../render/wikilinks"

module Xbookmark
  module Sync
    class ThreadIndex
      TOPIC_PREFIX_BYTES = 72
      LABEL_BYTES = 96

      def initialize(store: nil, bookmarks: [])
        @conversation_counts = Hash.new(0)
        @conversation_texts = {}
        @conversation_slugs = {}
        Array(bookmarks).each { |bookmark| add_bookmark(bookmark) }
        Array(store&.bookmarks).each { |row| add_row(row) }
        Array(store&.pages("thread")).each { |row| add_page(row) }
      end

      def thread_for(bookmark)
        conversation = bookmark.conversation_id.to_s
        return nil if conversation.empty?
        return nil if singleton?(bookmark)

        @conversation_texts[conversation] = bookmark.text.to_s if @conversation_texts[conversation].to_s.strip.empty?
        slug = @conversation_slugs[conversation] ||= self.class.slug_for(conversation: conversation, text: @conversation_texts[conversation])
        { slug: slug, target: "threads/#{slug}", label: self.class.label_for(text: @conversation_texts[conversation], fallback_slug: slug) }
      end

      def real_thread?(bookmark)
        !thread_for(bookmark).nil?
      end

      def add_bookmark(bookmark)
        conversation = bookmark.conversation_id.to_s
        @conversation_counts[conversation] += 1 unless conversation.empty?
        text = bookmark.text.to_s
        @conversation_texts[conversation] ||= text if !conversation.empty? && !text.strip.empty?
      end

      def add_bookmarks(bookmarks)
        Array(bookmarks).each { |bookmark| add_bookmark(bookmark) }
      end

      def self.slug_for(conversation:, text: nil)
        conversation_slug = Xbookmark::Render::Wikilinks.slug(conversation)
        topic = topic_slug(text)
        return "thread-#{conversation_slug}" if topic.empty?

        "thread-#{truncate_bytes(topic, TOPIC_PREFIX_BYTES)}-#{conversation_slug}"
      end

      def self.label_for(text:, fallback_slug:)
        label = text.to_s.lines.first.to_s
        label = label.gsub(%r{https?://\S+}, "").gsub(/\s+/, " ").strip
        label = fallback_slug.to_s.delete_prefix("thread-").tr("-", " ") if label.empty?
        "Thread: #{truncate_bytes(label, LABEL_BYTES)}"
      end

      private

      def add_row(row)
        payload = row[:payload_json].to_s.empty? ? nil : JSON.parse(row[:payload_json])
        data = Array(payload && payload["data"]).first || {}
        conversation = data["conversation_id"] || row[:tweet_id]
        @conversation_counts[conversation.to_s] += 1 unless conversation.to_s.empty?
        text = data["text"].to_s
        @conversation_texts[conversation.to_s] ||= text if !conversation.to_s.empty? && !text.strip.empty?
      rescue JSON::ParserError
        @conversation_counts[row[:tweet_id].to_s] += 1
      end

      def add_page(row)
        slug = row[:slug].to_s
        conversation = slug[/(\d+)\z/, 1] || slug.delete_prefix("thread-")
        return if conversation.empty?

        @conversation_counts[conversation] += 2
        @conversation_slugs[conversation] = slug unless placeholder_slug?(slug) || slug.match?(/\A\d+\z/)
      end

      def singleton?(bookmark)
        conversation = bookmark.conversation_id.to_s
        @conversation_counts[conversation] < 2 && conversation == bookmark.tweet_id.to_s
      end

      def placeholder_slug?(slug)
        slug.match?(/\Athread-\d+\z/)
      end

      def self.topic_slug(text)
        slug = Xbookmark::Render::Wikilinks.slug(text.to_s.lines.first.to_s)
        %w[untitled thread].include?(slug) ? "" : slug
      end

      def self.truncate_bytes(value, max)
        out = +""
        value.to_s.each_char do |char|
          break if (out + char).bytesize > max

          out << char
        end
        out.gsub(/-+\z/, "")
      end
    end
  end
end
