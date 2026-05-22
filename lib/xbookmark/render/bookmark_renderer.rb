# frozen_string_literal: true

require "yaml"
require "json"
require "time"
require "fileutils"
require "digest"
require "pathname"
require_relative "wikilinks"
require_relative "atomic_writer"

module Xbookmark
  module Render
    SCHEMA_VERSION = 1

    class BookmarkRenderer
      def initialize(vault_path:)
        @vault_path = vault_path
      end

      # Final markdown path inside the bookmark wiki.
      def markdown_path_for(bookmark)
        date_dir = bookmark_date(bookmark).strftime("%Y/%m/%d")
        File.join(@vault_path, "bookmarks", date_dir, "#{bookmark.tweet_id}.md")
      end

      def media_dir_for(bookmark)
        File.join(@vault_path, "media", bookmark.tweet_id.to_s)
      end

      # Renders to a Markdown string. Pure function over inputs.
      def render(bookmark, enrichment, media_records: [], transcripts: {}, link_blobs: [])
        front = frontmatter(bookmark, enrichment, media_records)
        body = body_for(bookmark, enrichment, media_records, transcripts, link_blobs)
        "---\n#{front.to_yaml(line_width: -1).sub(/^---\n?/, "")}---\n\n#{body}"
      end

      def write(bookmark, content)
        path = markdown_path_for(bookmark)
        AtomicWriter.write(path, content)
        path
      end

      def digest(enrichment, bookmark)
        canonical = {
          tweet_id: bookmark.tweet_id,
          summary: enrichment.summary,
          tags: (enrichment.tags || []).sort,
          topics: (enrichment.topics || []).sort,
          entities: (enrichment.entities || []).sort,
          links: (enrichment.links || []).map { |l| l["url"] }.sort
        }
        Digest::SHA256.hexdigest(JSON.generate(canonical))
      end

      private

      def bookmark_date(bookmark)
        Time.parse(bookmark.bookmarked_at.to_s).utc
      rescue ArgumentError
        # Fall back to created_at instead of Time.now — using "now" placed
        # the same bookmark in different YYYY/MM/DD directories on retry,
        # orphaning earlier files. created_at is stable across retries.
        Time.parse(bookmark.created_at.to_s).utc
      end

      def frontmatter(bookmark, enrichment, media_records)
        {
          "xbookmark_schema" => SCHEMA_VERSION,
          "tweet_id" => bookmark.tweet_id.to_s,
          "author" => bookmark.author_handle.to_s,
          "author_id" => bookmark.author_id.to_s,
          "author_name" => bookmark.author_name.to_s,
          "created_at" => bookmark.created_at.to_s,
          "bookmarked_at" => bookmark.bookmarked_at.to_s,
          "tags" => (enrichment.tags || []),
          "topics" => (enrichment.topics || []),
          "entities" => (enrichment.entities || []),
          "media" => media_records.map { |m| { "path" => relativize(m[:path]), "kind" => m[:kind], "alt" => m[:alt_text] } },
          "media_files" => media_records.map { |m| "[[#{relativize(m[:path])}]]" },
          "thread" => bookmark.conversation_id.to_s,
          "links" => (enrichment.links || []).map { |l| l.is_a?(Hash) ? l["url"] : l }.compact,
          "summary" => enrichment.summary,
          "enrichment_status" => enrichment.partial? ? "partial" : "done"
        }
      end

      def body_for(bookmark, enrichment, media_records, transcripts, link_blobs)
        sections = []
        sections << "# Tweet #{bookmark.tweet_id}"
        sections << enrichment.summary if enrichment.summary && !enrichment.summary.empty?
        sections << bookmark.text.to_s
        sections << author_section(bookmark)
        sections << topics_section(enrichment.topics)
        sections << entities_section(enrichment.entities)
        sections << media_section(bookmark, media_records, enrichment) unless media_records.empty?
        sections << transcripts_section(transcripts, enrichment) unless transcripts.empty?
        sections << quoted_section(bookmark) if bookmark.quoted_tweet_id
        sections << thread_section(bookmark) if bookmark.conversation_id
        sections << links_section(link_blobs) unless link_blobs.empty?
        sections << source_section(bookmark)
        sections.compact.join("\n\n").rstrip + "\n"
      end

      def author_section(bookmark)
        return nil unless bookmark.author_handle
        slug = Wikilinks.author_slug(bookmark.author_handle)
        "## Author\n\n#{Wikilinks.link("authors/#{slug}", "@#{bookmark.author_handle}")}"
      end

      def topics_section(topics)
        return nil if topics.nil? || topics.empty?
        items = topics.map { |t| "- #{Wikilinks.link("topics/#{Wikilinks.topic_slug(t)}", t)}" }
        "## Topics\n\n#{items.join("\n")}"
      end

      def entities_section(entities)
        return nil if entities.nil? || entities.empty?
        items = entities.map { |e| "- #{Wikilinks.link("entities/#{Wikilinks.entity_slug(e)}", e)}" }
        "## Entities\n\n#{items.join("\n")}"
      end

      def media_section(bookmark, records, enrichment)
        items = records.map do |m|
          rel = relativize(m[:path])
          direct_link = relative_to_note(bookmark, m[:path])
          # Obsidian's editing mode previews wikilink embeds (`![[…]]`)
          # natively for video/audio/images; raw <video> tags don't render.
          ["![[#{rel}]]", "[Open #{File.basename(m[:path])}](#{escape_markdown_url(direct_link)})"].join("\n")
        end
        out = ["## Media", *items]
        captions = enrichment.image_captions
        if captions && !captions.empty?
          out << "\nCaptions:"
          captions.each { |k, v| out << "- `#{k}`: #{v}" }
        end
        out.join("\n")
      end

      def transcripts_section(transcripts, enrichment)
        out = ["## Transcript"]
        summaries = enrichment.respond_to?(:transcript_summaries) ? enrichment.transcript_summaries || {} : {}
        formatted = enrichment.respond_to?(:formatted_transcripts) ? enrichment.formatted_transcripts || {} : {}
        transcripts.each do |k, v|
          parts = ["### #{k}"]
          summary = summaries[k] || summaries[File.basename(k.to_s)]
          parts << "#### Summary\n\n#{summary.to_s.strip}" if summary && !summary.to_s.strip.empty?

          transcript = formatted[k] || formatted[File.basename(k.to_s)]
          transcript = v if transcript.to_s.strip.empty?
          parts << "#### Transcript\n\n#{transcript.to_s.strip}"
          out << parts.join("\n\n")
        end
        out.join("\n\n")
      end

      def quoted_section(bookmark)
        text = bookmark.quoted_tweet ? bookmark.quoted_tweet["text"] : nil
        body = text ? "> #{text}" : "(quoted tweet not available)"
        "## Quoted\n\n#{body}\n\nQuoted tweet id: `#{bookmark.quoted_tweet_id}`"
      end

      def thread_section(bookmark)
        slug = bookmark.conversation_id.to_s
        return nil if slug.empty?
        "## Thread\n\n#{Wikilinks.link("threads/#{slug}", "thread #{slug}")}"
      end

      def links_section(link_blobs)
        items = link_blobs.map do |b|
          title = b[:title] || b[:url]
          "- [#{title}](#{b[:url]})"
        end
        "## Linked Articles\n\n#{items.join("\n")}"
      end

      def source_section(bookmark)
        url = bookmark.url
        url ? "## Source\n\n#{url}" : nil
      end

      def relativize(path)
        return path if path.nil?
        prefix = @vault_path.to_s.sub(/\/\z/, "")
        return path unless path.to_s.start_with?(prefix)
        path.to_s[(prefix.length + 1)..]
      end

      def relative_to_note(bookmark, path)
        note_dir = Pathname.new(File.dirname(markdown_path_for(bookmark)))
        Pathname.new(path).relative_path_from(note_dir).to_s
      rescue ArgumentError
        relativize(path)
      end

      def escape_markdown_url(path)
        path.to_s.gsub(" ", "%20").gsub("(", "%28").gsub(")", "%29")
      end
    end
  end
end
