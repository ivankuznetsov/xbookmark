# frozen_string_literal: true

require "yaml"
require "json"
require "fileutils"
require "digest"
require "pathname"
require_relative "wikilinks"
require_relative "atomic_writer"
require_relative "markdown_safety"
require_relative "path_builder"
require_relative "../taxonomy/concept"

module Xbookmark
  module Render
    SCHEMA_VERSION = 1

    class BookmarkRenderer
      def initialize(vault_path:, path_builder: nil)
        @vault_path = vault_path
        @path_builder = path_builder || PathBuilder.new(vault_path: vault_path)
      end

      # Final markdown path inside the bookmark wiki.
      def markdown_path_for(bookmark, enrichment: nil, existing_path: nil)
        @path_builder.path_for(bookmark, enrichment: enrichment, existing_path: existing_path)
      end

      def media_dir_for(bookmark)
        File.join(@vault_path, "media", bookmark.tweet_id.to_s)
      end

      # Renders to a Markdown string. Pure function over inputs.
      def render(bookmark, enrichment, media_records: [], transcripts: {}, link_blobs: [], thread: nil)
        front = frontmatter(bookmark, enrichment, media_records, thread: thread)
        body = body_for(bookmark, enrichment, media_records, transcripts, link_blobs, thread: thread)
        "---\n#{front.to_yaml(line_width: -1).sub(/^---\n?/, "")}---\n\n#{body}"
      end

      def write(bookmark, content, enrichment: nil, existing_path: nil)
        path = markdown_path_for(bookmark, enrichment: enrichment, existing_path: existing_path)
        AtomicWriter.write(path, content)
        path
      end

      def digest(enrichment, bookmark)
        canonical = {
          tweet_id: bookmark.tweet_id,
          title: title_value(enrichment),
          summary: enrichment.summary,
          tags: (enrichment.tags || []).sort,
          concepts: concepts_for(enrichment).map(&:slug).sort,
          links: (enrichment.links || []).map { |l| l["url"] }.sort
        }
        Digest::SHA256.hexdigest(JSON.generate(canonical))
      end

      private

      def frontmatter(bookmark, enrichment, media_records, thread:)
        concepts = concepts_for(enrichment)
        {
          "xbookmark_schema" => SCHEMA_VERSION,
          "title" => title_value(enrichment),
          "tweet_id" => bookmark.tweet_id.to_s,
          "author" => bookmark.author_handle.to_s,
          "author_id" => bookmark.author_id.to_s,
          "author_name" => bookmark.author_name.to_s,
          "created_at" => bookmark.created_at.to_s,
          "bookmarked_at" => bookmark.bookmarked_at.to_s,
          "tags" => MarkdownSafety.tags(enrichment.tags || []),
          "concepts" => concepts.map(&:slug),
          "concept_labels" => concepts.map(&:label),
          "facets" => MarkdownSafety.tags(concepts.flat_map(&:facets)),
          "media" => media_records.map { |m| { "path" => relativize(m[:path]), "kind" => m[:kind], "alt" => m[:alt_text] } },
          "media_files" => media_records.map { |m| "[[#{relativize(m[:path])}]]" },
          "conversation_id" => bookmark.conversation_id.to_s,
          "thread" => thread && thread[:target],
          "links" => (enrichment.links || []).map { |l| l.is_a?(Hash) ? l["url"] : l }.compact,
          "summary" => enrichment.summary,
          "enrichment_status" => enrichment.partial? ? "partial" : "done"
        }
      end

      def body_for(bookmark, enrichment, media_records, transcripts, link_blobs, thread:)
        sections = []
        sections << "# #{MarkdownSafety.wikilink_label(title_for(bookmark, enrichment))}"
        sections << enrichment.summary if enrichment.summary && !enrichment.summary.empty?
        sections << bookmark.text.to_s
        sections << author_section(bookmark)
        sections << concepts_section(concepts_for(enrichment))
        sections << media_section(bookmark, media_records, enrichment) unless media_records.empty?
        sections << transcripts_section(transcripts, enrichment) unless transcripts.empty?
        sections << quoted_section(bookmark) if bookmark.quoted_tweet_id
        sections << thread_section(thread) if thread
        sections << links_section(link_blobs) unless link_blobs.empty?
        sections << source_section(bookmark)
        sections.compact.join("\n\n").rstrip + "\n"
      end

      def author_section(bookmark)
        return nil unless bookmark.author_handle
        slug = Wikilinks.author_slug(bookmark.author_handle)
        "## Author\n\n#{Wikilinks.link("authors/#{slug}", "@#{bookmark.author_handle}")}"
      end

      def concepts_section(concepts)
        return nil if concepts.empty?

        items = concepts.map { |concept| "- #{Wikilinks.link("concepts/#{concept.slug}", concept.label)}" }
        "## Concepts\n\n#{items.join("\n")}"
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

      def thread_section(thread)
        "## Thread\n\n#{Wikilinks.link(thread[:target], thread[:label])}"
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

      def concepts_for(enrichment)
        Array(enrichment.concepts).map do |concept|
          next concept if concept.is_a?(Xbookmark::Taxonomy::Concept)
          if concept.is_a?(Hash)
            Xbookmark::Taxonomy::Concept.new(
              slug: concept["slug"] || concept[:slug] || concept["label"] || concept[:label],
              label: concept["label"] || concept[:label],
              kind: concept["kind"] || concept[:kind],
              aliases: concept["aliases"] || concept[:aliases],
              broader: concept["broader"] || concept[:broader],
              facets: concept["facets"] || concept[:facets]
            )
          else
            Xbookmark::Taxonomy::Concept.new(slug: concept)
          end
        end
      end

      # The concise enrichment title (already sanitized upstream), or nil when
      # absent. Drives the frontmatter `title` Property, the digest, and the
      # heading fallback so all three agree.
      def title_value(enrichment)
        enrichment.respond_to?(:title) ? enrichment.title : nil
      end

      def title_for(bookmark, enrichment)
        title = title_value(enrichment)
        return title if title && !title.to_s.strip.empty?

        [bookmark.author_handle && "@#{bookmark.author_handle}", enrichment.summary || bookmark.text || bookmark.tweet_id].compact.join(": ")
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
