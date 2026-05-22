# frozen_string_literal: true

require "json"
require_relative "codex"
require_relative "link_fetcher"

module Xbookmark
  module Enrich
    EnrichmentResult = Struct.new(
      :summary, :tags, :topics, :entities, :links,
      :image_captions, :image_ocr, :partial, :link_blobs,
      keyword_init: true
    ) do
      def partial?
        partial == true
      end
    end

    class Orchestrator
      PROMPT_DIR = File.expand_path("prompts", __dir__)

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
          "image_ocr" => { "type" => "object" }
        }
      }.freeze

      PLAN_SCHEMA = {
        "type" => "object",
        "properties" => {
          "fetch_external_links" => { "type" => "array", "items" => { "type" => "string" } },
          "summarize_quoted_tweet" => { "type" => "boolean" },
          "needs_image_ocr" => { "type" => "boolean" }
        }
      }.freeze

      attr_writer :existing_slugs

      def initialize(codex:, link_fetcher: nil, existing_slugs: [])
        @codex = codex
        @link_fetcher = link_fetcher || LinkFetcher.new
        @existing_slugs = existing_slugs
      end

      def enrich(bookmark, transcripts: {}, image_paths: [])
        plan = plan_call(bookmark, image_paths: image_paths)

        link_blobs = []
        if plan["fetch_external_links"]&.any?
          plan["fetch_external_links"].first(3).each do |url|
            blob = @link_fetcher.fetch(url)
            link_blobs << blob if blob
          end
        end

        vision =
          if plan["needs_image_ocr"] && image_paths.any?
            vision_call(image_paths)
          else
            { "captions" => {}, "ocr" => {} }
          end

        final = final_call(bookmark, transcripts: transcripts, link_blobs: link_blobs, vision: vision, image_paths: image_paths)

        partial = false
        if (final["tags"] || []).empty? || (final["entities"] || []).empty?
          retried = retry_required_fields(bookmark, transcripts: transcripts, link_blobs: link_blobs, vision: vision, image_paths: image_paths)
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

      def plan_call(bookmark, image_paths:)
        prompt = render_template("plan.txt", {
                                   tweet_text: bookmark.text.to_s,
                                   author_handle: bookmark.author_handle.to_s,
                                   author_name: bookmark.author_name.to_s,
                                   media_summary: media_summary_for(bookmark),
                                   has_quoted: bookmark.quoted_tweet_id ? "yes" : "no",
                                   external_links: format_links(bookmark.urls)
                                 })
        @codex.run(prompt: prompt, json_schema: PLAN_SCHEMA)
      end

      def vision_call(image_paths)
        prompt = render_template("vision.txt", {})
        @codex.run(prompt: prompt, images: image_paths,
                   json_schema: { "type" => "object", "properties" => { "captions" => { "type" => "object" }, "ocr" => { "type" => "object" } } })
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
        @codex.run(prompt: prompt, images: image_paths, json_schema: FINAL_SCHEMA)
      end

      def retry_required_fields(bookmark, **args)
        prompt_extra = "\n\nIMPORTANT: tags AND entities arrays MUST contain at least one entry each. " \
                       "Re-derive both from the tweet, transcripts, vision, and link extracts. " \
                       "Return JSON only with the same schema."
        @codex.run(prompt: build_retry_prompt(bookmark, **args, extra: prompt_extra), images: args[:image_paths], json_schema: FINAL_SCHEMA)
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

      def media_summary_for(bookmark)
        return "none" if bookmark.media.nil? || bookmark.media.empty?
        bookmark.media.map { |m| "#{m.type}#{m.alt_text ? " (alt: #{m.alt_text[0, 60]})" : ""}" }.join(", ")
      end

      def format_links(urls)
        return "none" if urls.nil? || urls.empty?
        urls.map { |u| u[:expanded_url] || u[:url] }.compact.first(3).join(", ")
      end

      def format_vision(vision)
        captions = (vision["captions"] || {}).map { |k, v| "#{k}: #{v}" }.join("\n")
        ocr = (vision["ocr"] || {}).map { |k, v| "#{k}: #{v}" }.join("\n")
        ["captions:\n#{captions}", "ocr:\n#{ocr}"].join("\n")
      end

      def format_link_blobs(blobs)
        blobs.map { |b| "[#{b[:title]}] (#{b[:url]})\n#{b[:text][0, 1500]}" }.join("\n---\n")
      end

      def render_template(name, vars)
        path = File.join(PROMPT_DIR, name)
        File.read(path) % vars
      end
    end
  end
end
