# frozen_string_literal: true

require "fileutils"
require "json"

require_relative "../media/downloader"
require_relative "../transcribe/whisper"
require_relative "../enrich/orchestrator"
require_relative "../render/bookmark_renderer"
require_relative "../render/aux_page"
require_relative "../render/concept_page"
require_relative "../render/concept_index"
require_relative "../taxonomy/normalizer"
require_relative "../taxonomy/registry"
require_relative "thread_index"

module Xbookmark
  module Sync
    # Per-bookmark transactional pipeline:
    # 1. media download into scratch
    # 2. whisper transcription (best-effort; missing binary => transient)
    # 3. codex enrichment (external links -> final call)
    # 4. atomic move of media dir + atomic .md write
    # 5. ensure aux pages exist (after the bookmark write succeeds)
    class Pipeline
      Outcome = Struct.new(:status, :error, :markdown_path, :digest, :partial, keyword_init: true)

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
        registry = Xbookmark::Taxonomy::Registry.from_vault(@config.vault_path, store: @store)
        @orch.concept_registry = registry if @orch.respond_to?(:concept_registry=)
        @orch.existing_slugs = @store.concept_slugs if @orch.respond_to?(:existing_slugs=)
        enrichment = @orch.enrich(bookmark, transcripts: transcripts, image_paths: image_paths(media_records))
        enrichment.concepts = normalize_concepts(enrichment.concepts, registry: registry)

        # Move scratch media into the final bookmark wiki location.
        media_records = move_media_into_wiki(bookmark, media_records)

        thread = Xbookmark::Sync::ThreadIndex.new(store: @store).thread_for(bookmark)
        existing_path = @store.find_bookmark(bookmark.tweet_id)&.dig(:markdown_path)
        markdown = @renderer.render(bookmark, enrichment, media_records: media_records, transcripts: transcripts,
                                    link_blobs: Array(enrichment.link_blobs), thread: thread)
        markdown_path = @renderer.write(bookmark, markdown, enrichment: enrichment, existing_path: existing_path)
        digest = @renderer.digest(enrichment, bookmark)

        ensure_aux_pages(bookmark, enrichment, thread: thread)

        FileUtils.rm_rf(scratch)
        Outcome.new(status: :done, markdown_path: markdown_path, digest: digest, partial: enrichment.partial?)
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

      def normalize_concepts(candidates, registry:)
        Xbookmark::Taxonomy::Normalizer.new(registry: registry).normalize_candidates(candidates)
      end

      def ensure_aux_pages(bookmark, enrichment, thread:)
        aux_orchestrator = @config.respond_to?(:aux_summaries) && @config.aux_summaries ? @orch : nil
        author = Xbookmark::Render::Wikilinks.author_slug(bookmark.author_handle)
        author_page = Xbookmark::Render::AuthorPage.new(vault_path: @config.vault_path, store: @store, orchestrator: aux_orchestrator)
        snippet = bookmark.text.to_s
        author_page.ensure!(slug: author, label: "@#{bookmark.author_handle}", inputs: [snippet])

        concept_page = Xbookmark::Render::ConceptPage.new(vault_path: @config.vault_path, store: @store)
        Array(enrichment.concepts).each do |concept|
          # Each bookmark contributes one unit of evidence; the store
          # accumulates across bookmarks (see Store#upsert_concept).
          attrs = concept.to_h.transform_keys(&:to_sym)
          attrs[:evidence_count] = 1
          @store.upsert_concept(**attrs)
          concept_page.ensure!(concept)
        end
        # Rebuild the index from the full concept set so it reflects the whole
        # taxonomy, not just this bookmark's concepts.
        all_concepts = @store.concepts.map { |row| Xbookmark::Taxonomy::Registry.concept_from_row(row) }
        conflicts = all_concepts.count { |concept| !concept.canonical? }
        Xbookmark::Render::ConceptIndex.new(vault_path: @config.vault_path).write(all_concepts, conflicts: conflicts)

        if thread
          thread_page = Xbookmark::Render::ThreadPage.new(vault_path: @config.vault_path, store: @store, orchestrator: @orch)
          thread_page.ensure!(slug: thread[:slug], label: thread[:label], inputs: [snippet])
        end
      end
    end
  end
end
