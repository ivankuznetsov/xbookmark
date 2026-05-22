# frozen_string_literal: true

require "fileutils"
require "time"
require_relative "report"
require_relative "pipeline"
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
        when :backfill_limited then backfill(report, limit: limit || 100)
        when :backfill_full    then backfill(report, limit: nil)
        when :sync             then incremental_sync(report)
        when :resync           then resync_one(report, tweet_id: tweet_id)
        else
          raise ArgumentError, "unknown mode: #{mode}"
        end

        # Only stamp last_sync_finished_at on a real run — a rejected
        # bootstrap (e.g. fresh-mode incremental sync) would otherwise pin
        # the throttle window and cause the next scheduled invocation to
        # skip even though no actual sync happened.
        @store.mark_sync_finished! if real_run?(report)
        reindex_qmd if report.synced.positive?
        report
      end

      def real_run?(report)
        report.synced.positive? || report.permanent_errors.zero?
      end

      private

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

      def backfill(report, limit:)
        if limit && @store.mode == Xbookmark::State::Store::MODE_FRESH
          @store.mode = Xbookmark::State::Store::MODE_FRESH # noop, but keep flow visible
        end
        retry_first(report)
        # New pages from API
        process_new_pages(report, limit: limit)
        if limit
          @store.mode = Xbookmark::State::Store::MODE_TEST_BACKFILLED
        else
          @store.mark_full_backfill_complete!
          @store.mode = Xbookmark::State::Store::MODE_FULLY_BACKFILLED
        end
      end

      def incremental_sync(report)
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
        retry_first(report)
        process_new_pages(report, limit: nil, only_new: true)
        @store.mode = Xbookmark::State::Store::MODE_INCREMENTAL
      end

      def resync_one(report, tweet_id:)
        raise ArgumentError, "resync requires a tweet_id" if tweet_id.to_s.empty?
        page = @x_client.get_tweet(tweet_id)
        bookmarks = Xbookmark::X::Expansions.new({ "data" => [page["data"]], "includes" => page["includes"] || {}, "meta" => {} }).bookmarks
        bm = bookmarks.first
        @store.upsert_pending(tweet_id: bm.tweet_id, author_handle: bm.author_handle, bookmarked_at: bm.bookmarked_at)
        @store.reset_to_pending!(bm.tweet_id)
        run_one(bm, report)
      end

      def retry_first(report)
        @store.bookmarks_to_retry(limit: 200).each do |row|
          # Reconstruct a Bookmark by re-fetching from X — keeps it simple.
          page = @x_client.get_tweet(row[:tweet_id])
          next unless page && page["data"]
          bm = Xbookmark::X::Expansions.new({ "data" => [page["data"]], "includes" => page["includes"] || {}, "meta" => {} }).bookmarks.first
          run_one(bm, report)
        end
      rescue Xbookmark::AuthError => e
        warn "[xbookmark] auth error during retry: #{e.message}"
        report.permanent_errors += 1
      end

      def process_new_pages(report, limit:, only_new: false)
        cursor = only_new ? @store.cursor : nil
        collected = 0
        @x_client.bookmarks(user_id: @config.x_user_id, pagination_token: cursor, max_results: 100) do |payload|
          report.api_pages += 1
          page_bookmarks = Xbookmark::X::Expansions.new(payload).bookmarks

          page_bookmarks.each do |bm|
            break if limit && collected >= limit
            @store.upsert_pending(tweet_id: bm.tweet_id, author_handle: bm.author_handle, bookmarked_at: bm.bookmarked_at)
            if @store.already_done?(bm.tweet_id)
              report.skipped += 1
              next
            end
            run_one(bm, report)
            collected += 1
          end

          next_token = (payload["meta"] || {})["next_token"]
          @store.cursor = next_token if next_token
          break if limit && collected >= limit
          break unless next_token
        end
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
    end
  end
end
