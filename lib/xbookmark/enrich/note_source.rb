# frozen_string_literal: true

require "yaml"
require "date"
require_relative "../x/bookmark"

module Xbookmark
  module Enrich
    # Reconstructs the enrichment inputs for an already-rendered bookmark note so
    # it can be re-enriched offline, without re-fetching from X. Everything the
    # enrichment needs — the original tweet text, media captions, and video
    # transcripts — is preserved in the rendered note by
    # BookmarkRenderer#body_for; this reverses that layout.
    class NoteSource
      Parsed = Struct.new(:bookmark, :transcripts, :vision, :media_records, :image_paths, :schema, :path,
                          keyword_init: true)

      PERMITTED_YAML = [Date, Time].freeze

      def self.parse(path, vault_path:)
        new(path, vault_path: vault_path).parse
      end

      def initialize(path, vault_path:)
        @path = path
        @vault_path = vault_path.to_s
      end

      # Returns a Parsed struct, or nil when the note has no usable frontmatter.
      def parse
        front, body = split_front_and_body(File.read(@path))
        return nil unless front && front["tweet_id"]

        Parsed.new(
          bookmark: build_bookmark(front, body),
          transcripts: parse_transcripts(body),
          # Reuse the captions the original run produced instead of paying for a
          # fresh vision pass; image_paths stays empty so no images are sent.
          vision: { "captions" => parse_captions(body), "ocr" => {} },
          media_records: media_records(front),
          image_paths: [],
          schema: front["xbookmark_schema"],
          path: @path
        )
      end

      private

      def split_front_and_body(raw)
        parts = raw.split(/^---\s*$/, 3)
        return [nil, nil] if parts.size < 3

        [YAML.safe_load(parts[1], permitted_classes: PERMITTED_YAML) || {}, parts[2]]
      rescue Psych::SyntaxError
        [nil, nil]
      end

      def build_bookmark(front, body)
        Xbookmark::X::Bookmark.new(
          tweet_id: front["tweet_id"].to_s,
          author_id: front["author_id"].to_s,
          author_handle: front["author"],
          author_name: front["author_name"],
          created_at: stringify_date(front["created_at"]),
          bookmarked_at: stringify_date(front["bookmarked_at"]),
          text: original_text(front, body),
          media: bookmark_media(front),
          urls: Array(front["links"]).map { |url| { "expanded_url" => url.to_s } },
          conversation_id: front["conversation_id"] || front["thread"]
        )
      end

      # The body BookmarkRenderer emits is: "# <title>", an optional summary
      # paragraph, the original tweet text, then "## ..." sections. Recover the
      # tweet text from the region before the first "## " heading, dropping the
      # title line and the known summary paragraph. Notes whose body is nothing
      # but the summary (35 in production) fall back to the summary itself.
      def original_text(front, body)
        head = body.to_s.split(/^##\s/, 2).first.to_s
        head = head.sub(/\A\s*#\s.*$/, "").strip
        summary = front["summary"].to_s.strip
        head = head.sub(summary, "").strip unless summary.empty?
        head.empty? ? summary : head
      end

      def parse_captions(body)
        section = section_text(body, "Media")
        return {} unless section

        section.each_line.with_object({}) do |line, captions|
          next unless (match = line.strip.match(/\A-\s+`([^`]+)`:\s*(.+)\z/))

          captions[match[1]] = match[2].strip
        end
      end

      def parse_transcripts(body)
        section = section_text(body, "Transcript")
        return {} unless section

        section.split(/^###\s+/).drop(1).each_with_object({}) do |chunk, out|
          key = chunk.lines.first.to_s.strip
          next if key.empty?

          match = chunk.match(/^####\s*Transcript\s*\n+(.*)\z/m)
          out[key] = match[1].split(/^####\s/).first.to_s.strip if match
        end
      end

      # Capture the text under "## <heading>" up to the next "## " (or EOF).
      def section_text(body, heading)
        match = body.to_s.match(/^##\s+#{Regexp.escape(heading)}\b(.*?)(?=^##\s|\z)/m)
        match && match[1]
      end

      def media_records(front)
        media_entries(front).map do |rel, kind, alt|
          { path: File.join(@vault_path, rel), kind: kind, alt_text: alt }
        end
      end

      def bookmark_media(front)
        media_entries(front).map do |rel, kind, alt|
          Xbookmark::X::Media.new(media_key: File.basename(rel), type: kind, url: nil, alt_text: alt)
        end
      end

      def media_entries(front)
        Array(front["media"]).filter_map do |m|
          rel = (m["path"] || m[:path]).to_s
          next if rel.empty?

          [rel, (m["kind"] || m[:kind]).to_s, m["alt"] || m[:alt]]
        end
      end

      def stringify_date(value)
        value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
      end
    end
  end
end
