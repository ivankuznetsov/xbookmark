# frozen_string_literal: true

require "fileutils"
require "time"
require_relative "report"
require_relative "pipeline"
require_relative "../x/client"
require_relative "../x/expansions"
require_relative "../enrich/codex"
require_relative "../enrich/orchestrator"
require_relative "../render/bookmark_renderer"
require_relative "../qmd/registrar"

module Xbookmark
  module Sync
    class Runner
      def initialize(config:, store:, x_client:, orchestrator: nil, renderer: nil, pipeline: nil, registrar: nil)
        @config = config
        @store = store
        @x_client = x_client
        @renderer = renderer || Xbookmark::Render::BookmarkRenderer.new(vault_path: config.vault_path)
        @orch = orchestrator || default_orchestrator
        @pipeline = pipeline || Xbookmark::Sync::Pipeline.new(config: config, store: store, orchestrator: @orch, renderer: @renderer)
        @registrar = registrar
      end

      # mode: :backfill_limited | :backfill_full | :sync | :resync
      def run(mode:, limit: nil, tweet_id: nil, from_scheduler: false)
        report = Report.new
        if from_scheduler && skip_due_to_recent?
          puts "[xbookmark] skipping; last sync was #{minutes_since_last_sync}m ago (< #{(@config.min_run_interval_hours * 60).to_i}m threshold)"
          return report
        end

        @store.mark_sync_started!
        FileUtils.mkdir_p(@config.scratch_dir)
        cleanup_stale_scratch

        case mode
        when :backfill_limited then backfill(report, limit: limit || 100, from_scheduler: from_scheduler)
        when :backfill_full    then backfill(report, limit: nil, from_scheduler: from_scheduler)
        when :sync             then incremental_sync(report, from_scheduler: from_scheduler)
        when :resync           then resync_one(report, tweet_id: tweet_id)
        else
          raise ArgumentError, "unknown mode: #{mode}"
        end

        # Only stamp last_sync_finished_at on a real run — a rejected
        # bootstrap (e.g. fresh-mode incremental sync) would otherwise pin
        # the throttle window and cause the next scheduled invocation to
        # skip even though no actual sync happened.
        @store.mark_sync_finished! if real_run?(report)
        run_maintenance(force: from_scheduler || report.synced.positive?)
        report
      end

      def real_run?(report)
        report.source_errors.zero? && (report.synced.positive? || report.permanent_errors.zero?)
      end

      private

      def run_maintenance(force: false)
        reindex_qmd if force
      end

      def reindex_qmd
        registrar = @registrar || Xbookmark::Qmd::Registrar.new(config: @config)
        # Make sync self-healing wrt registration so a clean install can
        # search a freshly-indexed collection without requiring
        # `xbookmark install` to have run first.
        registrar.ensure_registered! if registrar.respond_to?(:ensure_registered!)
        registrar.index!
      rescue StandardError => e
        warn "[xbookmark] qmd reindex failed: #{e.message}"
      end

      def default_orchestrator
        codex = Xbookmark::Enrich::Codex.new(bin: @config.codex_bin)
        Xbookmark::Enrich::Orchestrator.new(codex: codex)
      end

      def skip_due_to_recent?
        last = @store.last_sync_finished_at
        return false unless last
        diff = Time.now.utc - last.utc
        diff < (@config.min_run_interval_hours * 3600)
      end

      def minutes_since_last_sync
        last = @store.last_sync_finished_at
        return 0 unless last
        ((Time.now.utc - last.utc) / 60).to_i
      end

      def cleanup_stale_scratch
        Dir.glob(File.join(@config.scratch_dir, "*")).each do |dir|
          FileUtils.rm_rf(dir) if File.directory?(dir)
        end
      end

      def backfill(report, limit:, from_scheduler:)
        if limit && @store.mode == Xbookmark::State::Store::MODE_FRESH
          @store.mode = Xbookmark::State::Store::MODE_FRESH # noop, but keep flow visible
        end
        retry_first(report, tolerate_source_errors: from_scheduler)
        # New pages from API
        process_new_pages(report, limit: limit, tolerate_source_errors: from_scheduler)
        return if report.source_errors.positive?

        if limit
          @store.mode = Xbookmark::State::Store::MODE_TEST_BACKFILLED
        else
          @store.mark_full_backfill_complete!
          @store.mode = Xbookmark::State::Store::MODE_FULLY_BACKFILLED
        end
      end

      def incremental_sync(report, from_scheduler:)
        if @store.mode == Xbookmark::State::Store::MODE_FRESH
          puts "[xbookmark] bookmark wiki is empty. Run `xbookmark backfill --limit 100` first to seed it."
          report.permanent_errors += 1
          return
        end
        if @store.mode == Xbookmark::State::Store::MODE_TEST_BACKFILLED
          puts "[xbookmark] bookmark wiki was test-backfilled. Run `xbookmark backfill` (no --limit) to ingest the rest."
          report.permanent_errors += 1
          return
        end
        retry_first(report, tolerate_source_errors: from_scheduler)
        process_new_pages(report, limit: nil, only_new: true, tolerate_source_errors: from_scheduler)
        @store.mode = Xbookmark::State::Store::MODE_INCREMENTAL
      end

      def resync_one(report, tweet_id:)
        raise ArgumentError, "resync requires a tweet_id" if tweet_id.to_s.empty?
        page = @x_client.get_tweet(tweet_id)
        bookmarks = Xbookmark::X::Expansions.new({ "data" => [page["data"]], "includes" => page["includes"] || {}, "meta" => {} }).bookmarks
        bm = bookmarks.first
        @store.upsert_pending(tweet_id: bm.tweet_id, author_handle: bm.author_handle, bookmarked_at: bm.bookmarked_at,
                              payload: payload_for_bookmark(page, bm))
        @store.reset_to_pending!(bm.tweet_id)
        run_one(bm, report)
      end

      def retry_first(report, tolerate_source_errors:)
        rows = @store.bookmarks_to_process(limit: 200)
        uncached = []
        rows.each do |row|
          bm = cached_bookmark(row[:tweet_id])
          if bm
            run_one(bm, report)
          else
            uncached << row
          end
        end

        uncached.each do |row|
          bm = fetch_bookmark(row[:tweet_id])
          next unless bm

          run_one(bm, report)
        end
      rescue Xbookmark::AuthError, Xbookmark::RateLimited, Xbookmark::TransientError => e
        source_blocked(report, e, context: "retry", tolerate: tolerate_source_errors)
      end

      def process_new_pages(report, limit:, only_new: false, tolerate_source_errors:)
        collected = 0
        @x_client.bookmarks(user_id: @config.x_user_id,
                            max_results: Xbookmark::X::Client::BOOKMARK_PAGE_SIZE) do |payload|
          report.api_pages += 1
          page_bookmarks = Xbookmark::X::Expansions.new(payload).bookmarks
          page_new = 0

          page_bookmarks.each do |bm|
            break if limit && collected >= limit
            @store.upsert_pending(tweet_id: bm.tweet_id, author_handle: bm.author_handle, bookmarked_at: bm.bookmarked_at,
                                  payload: payload_for_bookmark(payload, bm))
            if @store.already_done?(bm.tweet_id)
              report.skipped += 1
              next
            end
            run_one(bm, report)
            collected += 1
            page_new += 1
          end

          next_token = (payload["meta"] || {})["next_token"]
          break if only_new && page_new.zero?
          break if limit && collected >= limit
          break unless next_token
        end
      rescue Xbookmark::AuthError, Xbookmark::RateLimited, Xbookmark::TransientError => e
        source_blocked(report, e, context: "new bookmark fetch", tolerate: tolerate_source_errors)
      end

      def run_one(bookmark, report)
        outcome = @pipeline.process(bookmark)
        case outcome.status
        when :done
          @store.record_success(tweet_id: bookmark.tweet_id, markdown_path: outcome.markdown_path, digest: outcome.digest)
          report.synced += 1
        when :needs_retry
          @store.record_failure(tweet_id: bookmark.tweet_id, error: outcome.error&.message || "unknown")
          report.failed += 1
        when :permanent_error
          @store.record_failure(tweet_id: bookmark.tweet_id, error: outcome.error&.message || "permanent", permanent: true)
          report.permanent_errors += 1
        end
      end

      def cached_bookmark(tweet_id)
        payload = @store.payload_for(tweet_id)
        return nil unless payload

        Xbookmark::X::Expansions.new(payload).bookmarks.first
      end

      def fetch_bookmark(tweet_id)
        page = @x_client.get_tweet(tweet_id)
        return nil unless page && page["data"]

        payload = { "data" => [page["data"]], "includes" => page["includes"] || {}, "meta" => {} }
        bookmark = Xbookmark::X::Expansions.new(payload).bookmarks.first
        @store.store_payload!(tweet_id: tweet_id, payload: payload)
        bookmark
      end

      def payload_for_bookmark(payload, bookmark)
        { "data" => [bookmark.raw], "includes" => payload["includes"] || {}, "meta" => {} }
      end

      def source_blocked(report, error, context:, tolerate:)
        warn "[xbookmark] source blocked during #{context}: #{error.message}"
        report.source_errors += 1
        report.permanent_errors += 1 unless tolerate
      end
    end
  end
end
