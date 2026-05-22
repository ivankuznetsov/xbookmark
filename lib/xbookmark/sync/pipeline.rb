# frozen_string_literal: true

require "fileutils"
require "json"

require_relative "../media/downloader"
require_relative "../transcribe/whisper"
require_relative "../enrich/orchestrator"
require_relative "../render/bookmark_renderer"
require_relative "../render/aux_page"

module Xbookmark
  module Sync
    # Per-bookmark transactional pipeline:
    # 1. media download into scratch
    # 2. whisper transcription (best-effort; missing binary => transient)
    # 3. codex enrichment (plan -> external -> final)
    # 4. atomic move of media dir + atomic .md write
    # 5. ensure aux pages exist (after the bookmark write succeeds)
    class Pipeline
      Outcome = Struct.new(:status, :error, :markdown_path, :digest, keyword_init: true)

      def initialize(config:, store:, orchestrator:, renderer:, downloader: nil, whisper: nil)
        @config = config
        @store = store
        @orch = orchestrator
        @renderer = renderer
        @downloader = downloader || Xbookmark::Media::Downloader.new
        @whisper = whisper || Xbookmark::Transcribe::Whisper.new(binary: config.whisper_bin, model: config.whisper_model)
      end

      def process(bookmark)
        scratch = scratch_dir_for(bookmark)
        FileUtils.mkdir_p(scratch)
        media_scratch = File.join(scratch, "media")

        media_records = bookmark.media.empty? ? [] : @downloader.download(bookmark.media, media_scratch)
        transcripts = transcribe_videos(media_records)
        @orch.existing_slugs = @store.all_topic_slugs if @orch.respond_to?(:existing_slugs=)
        enrichment = @orch.enrich(bookmark, transcripts: transcripts, image_paths: image_paths(media_records))

        # Move scratch media into the final bookmark wiki location.
        media_records = move_media_into_wiki(bookmark, media_records)

        markdown = @renderer.render(bookmark, enrichment, media_records: media_records, transcripts: transcripts, link_blobs: Array(enrichment.link_blobs))
        markdown_path = @renderer.write(bookmark, markdown)
        digest = @renderer.digest(enrichment, bookmark)

        ensure_aux_pages(bookmark, enrichment)

        FileUtils.rm_rf(scratch)
        Outcome.new(status: :done, markdown_path: markdown_path, digest: digest)
      rescue Xbookmark::TransientError, Xbookmark::RateLimited => e
        # WhisperUnavailable, MediaError, and CodexError already inherit
        # from TransientError — the rescue list above covers all of them.
        FileUtils.rm_rf(scratch) if scratch
        Outcome.new(status: :needs_retry, error: e)
      rescue Xbookmark::PermanentError => e
        FileUtils.rm_rf(scratch) if scratch
        Outcome.new(status: :permanent_error, error: e)
      rescue StandardError => e
        # Coding bugs (NoMethodError, TypeError, SQLite3::Exception, ...)
        # are NOT transient — log the class and backtrace so they aren't
        # silently retried 3× against live X/codex APIs, then promote
        # straight to a permanent error.
        FileUtils.rm_rf(scratch) if scratch
        warn "[xbookmark] pipeline crashed for tweet #{bookmark.tweet_id}: #{e.class}: #{e.message}"
        warn e.backtrace.first(20).join("\n") if e.backtrace
        Outcome.new(status: :permanent_error, error: e)
      end

      private

      def scratch_dir_for(bookmark)
        File.join(@config.scratch_dir, bookmark.tweet_id.to_s)
      end

      def transcribe_videos(media_records)
        out = {}
        media_records.each do |m|
          next unless m[:kind] == "video" || m[:kind] == "animated_gif"
          duration = m[:duration_ms]
          next if duration && duration < Xbookmark::Transcribe::Whisper::MIN_DURATION_MS
          text = @whisper.transcribe(m[:path], duration_ms: duration)
          out[File.basename(m[:path])] = text unless text.to_s.empty?
        end
        out
      end

      def image_paths(media_records)
        media_records.select { |m| m[:kind] == "photo" }.map { |m| m[:path] }
      end

      def move_media_into_wiki(bookmark, media_records)
        return media_records if media_records.empty?
        final_dir = @renderer.media_dir_for(bookmark)
        FileUtils.mkdir_p(File.dirname(final_dir))
        FileUtils.rm_rf(final_dir) if File.exist?(final_dir)
        # Move the parent media dir from scratch
        scratch_media = File.dirname(media_records.first[:path])
        File.rename(scratch_media, final_dir)
        media_records.map do |m|
          m.merge(path: File.join(final_dir, File.basename(m[:path])))
        end
      end

      def ensure_aux_pages(bookmark, enrichment)
        aux_orchestrator = @config.respond_to?(:aux_summaries) && @config.aux_summaries ? @orch : nil
        author = Xbookmark::Render::Wikilinks.author_slug(bookmark.author_handle)
        author_page = Xbookmark::Render::AuthorPage.new(vault_path: @config.vault_path, store: @store, orchestrator: aux_orchestrator)
        snippet = bookmark.text.to_s
        author_page.ensure!(slug: author, label: "@#{bookmark.author_handle}", inputs: [snippet])

        topic_page = Xbookmark::Render::TopicPage.new(vault_path: @config.vault_path, store: @store, orchestrator: aux_orchestrator)
        Array(enrichment.topics).each do |t|
          topic_page.ensure!(slug: Xbookmark::Render::Wikilinks.topic_slug(t), label: t, inputs: [snippet])
        end

        entity_page = Xbookmark::Render::EntityPage.new(vault_path: @config.vault_path, store: @store, orchestrator: aux_orchestrator)
        Array(enrichment.entities).each do |e|
          entity_page.ensure!(slug: Xbookmark::Render::Wikilinks.entity_slug(e), label: e, inputs: [snippet])
        end

        if bookmark.conversation_id
          thread_page = Xbookmark::Render::ThreadPage.new(vault_path: @config.vault_path, store: @store, orchestrator: @orch)
          thread_page.ensure!(slug: bookmark.conversation_id.to_s, label: "thread #{bookmark.conversation_id}", inputs: [snippet])
        end
      end
    end
  end
end
