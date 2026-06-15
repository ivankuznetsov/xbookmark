# frozen_string_literal: true

require "json"
require "uri"
require_relative "codex"
require_relative "link_fetcher"

module Xbookmark
  module Enrich
    EnrichmentResult = Struct.new(
      :summary, :tags, :topics, :entities, :links,
      :image_captions, :image_ocr, :transcript_summaries,
      :formatted_transcripts, :partial, :link_blobs,
      keyword_init: true
    ) do
      def partial?
        partial == true
      end
    end

    class Orchestrator
      PROMPT_DIR = File.expand_path("prompts", __dir__)
      IMAGE_TIMEOUT = 300

      FINAL_SCHEMA = {
        "type" => "object",
        "required" => %w[tags topics entities],
        "properties" => {
          "summary" => { "type" => %w[string null] },
          "tags" => { "type" => "array", "items" => { "type" => "string" } },
          "topics" => { "type" => "array", "items" => { "type" => "string" } },
          "entities" => { "type" => "array", "items" => { "type" => "string" } },
          "links" => { "type" => "array" },
          "image_captions" => { "type" => "object" },
          "image_ocr" => { "type" => "object" },
          "transcript_summaries" => { "type" => "object" },
          "formatted_transcripts" => { "type" => "object" }
        }
      }.freeze

      attr_writer :existing_slugs

      def initialize(codex:, link_fetcher: nil, existing_slugs: [])
        @codex = codex
        @link_fetcher = link_fetcher || LinkFetcher.new
        @existing_slugs = existing_slugs
      end

      def enrich(bookmark, transcripts: {}, image_paths: [])
        link_blobs = fetch_link_blobs(bookmark)
        vision = { "captions" => {}, "ocr" => {} }

        partial = false
        final_image_paths = image_paths
        begin
          final = final_call(bookmark, transcripts: transcripts, link_blobs: link_blobs, vision: vision, image_paths: final_image_paths)
        rescue Xbookmark::CodexError, Xbookmark::PermanentError
          raise if Array(image_paths).empty?

          partial = true
          final_image_paths = []
          final = final_call(bookmark, transcripts: transcripts, link_blobs: link_blobs, vision: vision, image_paths: final_image_paths)
        end

        if (final["tags"] || []).empty? || (final["entities"] || []).empty?
          retried = retry_required_fields(bookmark, transcripts: transcripts, link_blobs: link_blobs, vision: vision, image_paths: final_image_paths)
          if retried && (retried["tags"] || []).any? && (retried["entities"] || []).any?
            final = retried
          else
            partial = true
            final["tags"] ||= []
            final["entities"] ||= []
          end
        end

        EnrichmentResult.new(
          summary: final["summary"],
          tags: Array(final["tags"]).map(&:to_s),
          topics: Array(final["topics"]).map(&:to_s),
          entities: Array(final["entities"]).map(&:to_s),
          links: Array(final["links"] || []),
          image_captions: final["image_captions"] || vision["captions"] || {},
          image_ocr: final["image_ocr"] || vision["ocr"] || {},
          transcript_summaries: string_object(final["transcript_summaries"]),
          formatted_transcripts: string_object(final["formatted_transcripts"]),
          partial: partial,
          link_blobs: link_blobs
        )
      end

      def summarize_topic(slug:, snippets:)
        prompt = render_template("summarize_topic.txt", { slug: slug, snippets: snippets.join("\n---\n") })
        result = @codex.run(prompt: prompt, json_schema: { "type" => "object", "required" => %w[summary] })
        result["summary"]
      end

      def summarize_author(handle:, snippets:)
        prompt = render_template("summarize_author.txt", { handle: handle, snippets: snippets.join("\n---\n") })
        result = @codex.run(prompt: prompt, json_schema: { "type" => "object", "required" => %w[summary] })
        result["summary"]
      end

      private

      def vision_call(image_paths)
        prompt = render_template("vision.txt", {})
        @codex.run(prompt: prompt, images: image_paths,
                   json_schema: { "type" => "object", "properties" => { "captions" => { "type" => "object" }, "ocr" => { "type" => "object" } } })
      end

      def fetch_link_blobs(bookmark)
        candidate_external_links(bookmark).first(3).filter_map { |url| @link_fetcher.fetch(url) }
      end

      def candidate_external_links(bookmark)
        Array(bookmark.urls).filter_map { |url| expanded_url(url) }.uniq.select { |url| external_article_url?(url) }
      end

      def expanded_url(url)
        return url if url.is_a?(String)
        url[:expanded_url] || url["expanded_url"] || url[:url] || url["url"]
      end

      def external_article_url?(url)
        uri = URI.parse(url.to_s)
        return false unless %w[http https].include?(uri.scheme)
        host = uri.host.to_s.downcase
        return false if host.empty?
        !x_host?(host)
      rescue URI::InvalidURIError
        false
      end

      def x_host?(host)
        host == "x.com" || host.end_with?(".x.com") ||
          host == "twitter.com" || host.end_with?(".twitter.com") ||
          host == "t.co" || host.end_with?(".t.co")
      end

      def final_call(bookmark, transcripts:, link_blobs:, vision:, image_paths:)
        prompt = render_template("final.txt", {
                                   tweet_text: bookmark.text.to_s,
                                   author_handle: bookmark.author_handle.to_s,
                                   quoted_text: (bookmark.quoted_tweet || {})["text"].to_s,
                                   transcripts: transcripts.map { |k, v| "[#{k}]\n#{v}" }.join("\n\n"),
                                   vision_blob: format_vision(vision),
                                   link_blobs: format_link_blobs(link_blobs),
                                   existing_slugs: @existing_slugs.first(50).join(", ")
                                 })
        @codex.run(prompt: prompt, images: image_paths, json_schema: FINAL_SCHEMA, timeout: timeout_for_images(image_paths))
      end

      def retry_required_fields(bookmark, **args)
        prompt_extra = "\n\nIMPORTANT: tags AND entities arrays MUST contain at least one entry each. " \
                       "Re-derive both from the tweet, transcripts, vision, and link extracts. " \
                       "Return JSON only with the same schema."
        @codex.run(prompt: build_retry_prompt(bookmark, **args, extra: prompt_extra), images: args[:image_paths],
                   json_schema: FINAL_SCHEMA, timeout: timeout_for_images(args[:image_paths]))
      rescue Xbookmark::CodexError, Xbookmark::PermanentError
        # Best-effort second pass — fall back to the first call's partial
        # result. A schema mismatch on the retry still leaves the original
        # response usable.
        nil
      end

      def build_retry_prompt(bookmark, transcripts:, link_blobs:, vision:, image_paths:, extra:)
        render_template("final.txt", {
                          tweet_text: bookmark.text.to_s,
                          author_handle: bookmark.author_handle.to_s,
                          quoted_text: (bookmark.quoted_tweet || {})["text"].to_s,
                          transcripts: transcripts.map { |k, v| "[#{k}]\n#{v}" }.join("\n\n"),
                          vision_blob: format_vision(vision),
                          link_blobs: format_link_blobs(link_blobs),
                          existing_slugs: @existing_slugs.first(50).join(", ")
                        }) + extra
      end

      def timeout_for_images(image_paths)
        Array(image_paths).empty? ? Xbookmark::Enrich::Codex::DEFAULT_TIMEOUT : IMAGE_TIMEOUT
      end

      def format_vision(vision)
        captions = (vision["captions"] || {}).map { |k, v| "#{k}: #{v}" }.join("\n")
        ocr = (vision["ocr"] || {}).map { |k, v| "#{k}: #{v}" }.join("\n")
        ["captions:\n#{captions}", "ocr:\n#{ocr}"].join("\n")
      end

      def format_link_blobs(blobs)
        blobs.map { |b| "[#{b[:title]}] (#{b[:url]})\n#{b[:text][0, 1500]}" }.join("\n---\n")
      end

      def string_object(value)
        return {} unless value.is_a?(Hash)
        value.each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_s }
      end

      def render_template(name, vars)
        path = File.join(PROMPT_DIR, name)
        File.read(path) % vars
      end
    end
  end
end
