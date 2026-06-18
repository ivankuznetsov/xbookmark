# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "report"
require_relative "pipeline"
require_relative "../x/client"
require_relative "../x/expansions"
require_relative "../browser/errors"
require_relative "../enrich/codex"
require_relative "../enrich/orchestrator"
require_relative "../render/bookmark_renderer"
require_relative "../qmd/registrar"
require_relative "../taxonomy/curator"
require_relative "../taxonomy/lock"
require_relative "../taxonomy/registry"
require_relative "../taxonomy/rebuilder"

module Xbookmark
  module Sync
    class Runner
      TAXONOMY_CURATION_BATCH_SIZE = 50
      TAXONOMY_CURATION_TIMEOUT_SECONDS = 60

      # Errors that block a single source without being a hard run failure: the
      # Runner isolates each via #source_blocked so the remaining sources keep
      # syncing (AC3). SessionExpired is an AuthError subclass (so it is covered
      # here) and ConfigError covers a misconfigured browser source, e.g. missing
      # Chromium. SourceUnavailable is intentionally excluded — it means a single
      # tweet is gone, not that the source is blocked.
      SOURCE_BLOCK_ERRORS = [
        Xbookmark::AuthError, Xbookmark::RateLimited, Xbookmark::TransientError, Xbookmark::ConfigError
      ].freeze

      # The duck-typed source contract get_tweet_any fully trusts (it drops its
      # respond_to? guard on the basis these are always present). Sources::Factory
      # enforces this at build time, but the Runner also accepts arbitrary
      # sources:/x_client: objects, so it must validate here too.
      CONTRACT_METHODS = %i[bookmarks get_tweet].freeze

      def initialize(config:, store:, sources: nil, x_client: nil, orchestrator: nil, renderer: nil, pipeline: nil, registrar: nil)
        @config = config
        @store = store
        # Generalized from a single x_client to an ordered list of sources so an
        # API source keeps syncing in the same run even when the browser session
        # has expired. `x_client:` stays as a back-compat single-element shim.
        @sources = sources ? Array(sources) : [x_client].compact
        # A run with zero sources fetches no pages yet still walks the
        # mark-backfilled / stamp-last_sync paths, sealing an empty store as a
        # successful backfill. Fail fast at construction instead — the Factory
        # always returns at least one source (or raises), so an empty list is a
        # wiring bug, not a valid configuration.
        raise ArgumentError, "Sync::Runner requires at least one source" if @sources.empty?

        # Validate the source contract at the boundary that trusts it (get_tweet_any
        # has no respond_to? guard), so a source missing a method surfaces as a
        # clear ConfigError here rather than a raw NoMethodError mid-run.
        @sources.each { |source| verify_source_contract!(source) }

        @renderer = renderer || Xbookmark::Render::BookmarkRenderer.new(vault_path: config.vault_path)
        @orch = orchestrator || default_orchestrator
        @pipeline = pipeline || Xbookmark::Sync::Pipeline.new(config: config, store: store, orchestrator: @orch,
                                                              renderer: @renderer, defer_concept_index: true)
        @registrar = registrar
      end

      # mode: :backfill_limited | :backfill_full | :sync | :resync
      def run(mode:, limit: nil, tweet_id: nil, from_scheduler: false)
        report = Report.new
        if from_scheduler && skip_due_to_recent?
          puts "[xbookmark] skipping; last sync was #{minutes_since_last_sync}m ago (< #{(@config.min_run_interval_hours * 60).to_i}m threshold)"
          return report
        end

        # Hold the taxonomy lock for the whole run so a concurrent invocation
        # (e.g. a manual `taxonomy rebuild --apply` firing while the scheduler
        # syncs) can never mutate the same files at the same time. Maintenance
        # reuses this lock via `locked: true`.
        lock = Xbookmark::Taxonomy::Lock.acquire(@config.vault_path)
        unless lock
          puts "[xbookmark] another xbookmark run holds the taxonomy lock; skipping this run"
          return report
        end

        begin
          @store.mark_sync_started!
          FileUtils.mkdir_p(@config.scratch_dir)
          cleanup_stale_scratch
          @pipeline.prepare_run! if @pipeline.respond_to?(:prepare_run!)

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
          @pipeline.finalize_run! if @pipeline.respond_to?(:finalize_run!)
          @store.mark_sync_finished! if real_run?(report)
          run_maintenance(force: from_scheduler || report.synced.positive?, report: report)
        ensure
          Xbookmark::Taxonomy::Lock.release(lock)
          close_sources
        end
        report
      end

      def real_run?(report)
        report.source_errors.zero? &&
          (report.bookmark_attempts.positive? || report.synced.positive? || report.permanent_errors.zero?)
      end

      private

      def run_maintenance(force: false, report: nil)
        taxonomy_report = run_taxonomy_maintenance(report) if force && taxonomy_maintenance?
        reindex_qmd if force && !(taxonomy_report && taxonomy_report.state == "applied")
      end

      def taxonomy_maintenance?
        @config.respond_to?(:taxonomy_maintenance) && @config.taxonomy_maintenance == true
      end

      def run_taxonomy_maintenance(sync_report = nil)
        registrar = @registrar || Xbookmark::Qmd::Registrar.new(config: @config)
        # locked: true — the run already holds the taxonomy lock.
        report = Xbookmark::Taxonomy::Rebuilder.new(config: @config, store: @store, registrar: registrar).call(apply: true, locked: true)
        if report.partial_failure?
          # Make destructive maintenance failures loud and persist them so the
          # next interactive run can surface them, rather than letting an
          # unattended timer hide them on stderr.
          sync_report.maintenance_errors += 1 if sync_report
          @store.set_meta("last_taxonomy_error", report.to_s)
          warn "[xbookmark] taxonomy maintenance PARTIAL FAILURE: #{report}"
        elsif !report.clean?
          warn "[xbookmark] #{report}"
        end
        if !report.partial_failure? && !run_taxonomy_curation
          sync_report.maintenance_errors += 1 if sync_report
        end
        report
      rescue StandardError => e
        sync_report.maintenance_errors += 1 if sync_report
        @store.set_meta("last_taxonomy_error", "#{e.class}: #{e.message}")
        warn "[xbookmark] taxonomy maintenance failed: #{e.class}: #{e.message}"
        nil
      end

      def run_taxonomy_curation
        candidates = taxonomy_curation_candidates
        return true if candidates.empty?

        registry = Xbookmark::Taxonomy::Registry.from_vault(@config.vault_path, store: @store)
        codex = Xbookmark::Enrich::Codex.new(bin: @config.codex_bin)
        Xbookmark::Taxonomy::Curator.new(
          codex: codex,
          registry: registry,
          store: @store,
          timeout: TAXONOMY_CURATION_TIMEOUT_SECONDS
        ).curate(candidates)
        true
      rescue StandardError => e
        @store.set_meta("last_taxonomy_error", "#{e.class}: #{e.message}")
        warn "[xbookmark] taxonomy curation failed: #{e.class}: #{e.message}"
        false
      end

      def taxonomy_curation_candidates
        @store.concepts
          .sort_by { |row| [row[:confidence].to_f, row[:updated_at].to_s, row[:slug].to_s] }
          .first(TAXONOMY_CURATION_BATCH_SIZE)
          .map { |row| Xbookmark::Taxonomy::Registry.concept_from_row(row).to_h }
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

      def backfill(report, limit:)
        if limit && @store.mode == Xbookmark::State::Store::MODE_FRESH
          @store.mode = Xbookmark::State::Store::MODE_FRESH # noop, but keep flow visible
        end
        attempted = retry_first(report)
        # New pages from API
        process_new_pages(report, limit: limit, attempted_ids: attempted)
        return if report.source_errors.positive?

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
        attempted = retry_first(report)
        process_new_pages(report, limit: nil, only_new: true, attempted_ids: attempted)
        @store.mode = Xbookmark::State::Store::MODE_INCREMENTAL
      end

      def resync_one(report, tweet_id:)
        raise ArgumentError, "resync requires a tweet_id" if tweet_id.to_s.empty?
        page = get_tweet_any(tweet_id)
        raise Xbookmark::SourceUnavailable, "tweet #{tweet_id} was unavailable from all sources" unless page && page["data"]
        bookmarks = Xbookmark::X::Expansions.new({ "data" => [page["data"]], "includes" => page["includes"] || {}, "meta" => {} }).bookmarks
        bm = bookmarks.first
        @store.upsert_pending(tweet_id: bm.tweet_id, author_handle: bm.author_handle, bookmarked_at: bm.bookmarked_at,
                              payload: payload_for_bookmark(page, bm))
        @store.reset_to_pending!(bm.tweet_id)
        run_one(bm, report)
      rescue *SOURCE_BLOCK_ERRORS => e
        # An expired browser session (or any source block) during resync must be
        # isolated like the sync/retry paths — record it and signal re-login
        # rather than escaping uncaught as a raw stacktrace.
        source_blocked(report, e, context: "resync")
      end

      def retry_first(report)
        rows = @store.bookmarks_to_process(limit: 200)
        attempted = {}
        uncached = []
        rows.each do |row|
          bm = cached_bookmark(row)
          if bm
            attempted[bm.tweet_id.to_s] = true
            run_one(bm, report)
          else
            uncached << row
          end
        end

        uncached.each do |row|
          bm = fetch_bookmark(row[:tweet_id])
          next unless bm

          attempted[bm.tweet_id.to_s] = true
          run_one(bm, report)
        rescue Xbookmark::SourceUnavailable => e
          attempted[row[:tweet_id].to_s] = true
          report.bookmark_attempts += 1
          @store.record_failure(tweet_id: row[:tweet_id], error: e.message, permanent: true)
          report.permanent_errors += 1
        end
        attempted
      rescue *SOURCE_BLOCK_ERRORS => e
        source_blocked(report, e, context: "retry")
        attempted || {}
      end

      def process_new_pages(report, limit:, only_new: false, attempted_ids: {})
        collected = 0
        @sources.each do |source|
          break if limit && collected >= limit

          collected = fetch_new_pages(source, report, limit: limit, only_new: only_new,
                                      attempted_ids: attempted_ids, collected: collected)
        end
      end

      # Drives one source's pagination. Any source block — auth, rate-limit, a
      # transient browser/CDP failure, or a missing-Chromium ConfigError — is
      # isolated via source_blocked so the remaining sources still run. Returns
      # the running `collected` count so `limit` caps total items across sources.
      def fetch_new_pages(source, report, limit:, only_new:, attempted_ids:, collected:)
        consumer_error = nil
        source.bookmarks(user_id: @config.x_user_id,
                         max_results: Xbookmark::X::Client::BOOKMARK_PAGE_SIZE) do |payload|
          begin
            report.source_pages += 1
            page_bookmarks = Xbookmark::X::Expansions.new(payload).bookmarks
            @pipeline.index_thread_bookmarks(page_bookmarks) if @pipeline.respond_to?(:index_thread_bookmarks)
            page_new = 0

            page_bookmarks.each do |bm|
              break if limit && collected >= limit
              @store.upsert_pending(tweet_id: bm.tweet_id, author_handle: bm.author_handle, bookmarked_at: bm.bookmarked_at,
                                    payload: payload_for_bookmark(payload, bm))
              if @store.already_done?(bm.tweet_id)
                report.skipped += 1
                next
              end
              next if attempted_ids[bm.tweet_id.to_s]

              run_one(bm, report)
              collected += 1
              page_new += 1
            end

            next_token = (payload["meta"] || {})["next_token"]
            break if only_new && page_new.zero?
            break if limit && collected >= limit
            break unless next_token
          rescue *SOURCE_BLOCK_ERRORS
            # A genuine source block raised while consuming a page is still the
            # source-block contract — let it reach the rescue below.
            raise
          rescue StandardError => e
            # The per-page consumer work (Expansions, the store, the pipeline) ran
            # inside the source's yield, so a non-source-block error here is the
            # consumer's, not the source's. Capture it and stop driving this source
            # cleanly so it is handled here — outside the source's own rescue —
            # rather than the browser source laundering it into a tolerated
            # TransientError, or a malformed API page (which X::Client does not
            # wrap) aborting the whole multi-source run with a raw stacktrace.
            consumer_error = e
            break
          end
        end
        consumer_failed(report, consumer_error, context: "new bookmark fetch") if consumer_error
        collected
      rescue *SOURCE_BLOCK_ERRORS => e
        source_blocked(report, e, context: "new bookmark fetch")
        collected
      end

      def run_one(bookmark, report)
        report.bookmark_attempts += 1
        outcome = @pipeline.process(bookmark)
        case outcome.status
        when :done
          @store.record_success(tweet_id: bookmark.tweet_id, markdown_path: outcome.markdown_path, digest: outcome.digest)
          report.synced += 1
          if outcome.partial
            report.partial += 1
            warn "[xbookmark] tweet #{bookmark.tweet_id} enriched with incomplete data (partial); will not auto-retry"
          end
        when :needs_retry
          status = @store.record_failure(tweet_id: bookmark.tweet_id, error: outcome.error&.message || "unknown")
          if status == Xbookmark::State::Store::STATUS_PERMANENT
            report.permanent_errors += 1
          else
            report.failed += 1
          end
        when :permanent_error
          @store.record_failure(tweet_id: bookmark.tweet_id, error: outcome.error&.message || "permanent", permanent: true)
          report.permanent_errors += 1
        end
      end

      def cached_bookmark(row)
        payload = cached_payload(row[:payload_json])
        return nil unless payload

        Xbookmark::X::Expansions.new(payload).bookmarks.first
      end

      def fetch_bookmark(tweet_id)
        page = get_tweet_any(tweet_id)
        raise Xbookmark::SourceUnavailable, "tweet #{tweet_id} was unavailable from any source" unless page && page["data"]

        payload = { "data" => [page["data"]], "includes" => page["includes"] || {}, "meta" => {} }
        bookmark = Xbookmark::X::Expansions.new(payload).bookmarks.first
        @store.store_payload!(tweet_id: tweet_id, payload: payload)
        bookmark
      end

      # Tries each source's get_tweet until one returns the tweet. A source
      # block (auth/rate-limit/transient) on one source does not abort the
      # others; if every source is blocked, the last block is re-raised so the
      # caller's source_blocked path records it.
      def get_tweet_any(tweet_id)
        last_block = nil
        @sources.each do |source|
          # get_tweet is a mandatory part of the source contract (enforced by
          # Sources::Factory#verify_contract!), so every source answers it — no
          # respond_to? guard, which would only mask a future contract violation.
          begin
            page = source.get_tweet(tweet_id)
            return page if page && page["data"]
          rescue Xbookmark::SourceUnavailable
            # This source does not have the tweet; try the next source.
            next
          rescue *SOURCE_BLOCK_ERRORS => e
            last_block = e
          end
        end
        raise last_block if last_block

        nil
      end

      def payload_for_bookmark(payload, bookmark)
        includes = payload["includes"] || {}
        referenced_ids = Array(bookmark.raw["referenced_tweets"]).filter_map { |ref| ref["id"] }
        media_keys = Array(bookmark.raw.dig("attachments", "media_keys"))
        {
          "data" => [bookmark.raw],
          "includes" => {
            "users" => filter_includes(includes["users"], "id", [bookmark.author_id]),
            "media" => filter_includes(includes["media"], "media_key", media_keys),
            "tweets" => filter_includes(includes["tweets"], "id", referenced_ids)
          },
          "meta" => {}
        }
      end

      def filter_includes(records, key, allowed)
        allowed = allowed.compact.map(&:to_s)
        return [] if allowed.empty?

        Array(records).select { |record| allowed.include?(record[key].to_s) }
      end

      def cached_payload(raw)
        return nil if raw.to_s.empty?

        payload = JSON.parse(raw)
        return nil unless payload.is_a?(Hash)
        return nil unless payload["data"].is_a?(Array) && payload["data"].all? { |tweet| tweet.is_a?(Hash) }
        return nil unless payload["includes"].nil? || payload["includes"].is_a?(Hash)

        payload
      rescue JSON::ParserError
        nil
      end

      def source_blocked(report, error, context:)
        warn "[xbookmark] source blocked during #{context}: #{error.message}"
        report.source_errors += 1
        # A browser session expiry is the one source block that needs a human:
        # set expired_source so the CLI fires a notification and exits non-zero
        # even under --from-scheduler (report.session_expired? derives from it).
        # A generic API token block leaves expired_source nil → exit-0 + degraded.
        report.mark_session_expired if error.is_a?(Xbookmark::Browser::SessionExpired)
      end

      # A consumer/store/pipeline error raised while processing a source's page is
      # neither a tolerated source block (it must not silently exit 0 and self-
      # retry forever under --from-scheduler) nor a reason to abort the sibling
      # sources (AC3). Record it as a source error so a backfill is not sealed
      # complete over an unprocessed tail, AND as a permanent error so the run
      # fails loudly even under --from-scheduler, then let the caller move on to
      # the next source.
      def consumer_failed(report, error, context:)
        warn "[xbookmark] #{context} failed while processing a source page: #{error.class}: #{error.message}"
        report.source_errors += 1
        report.permanent_errors += 1
      end

      def verify_source_contract!(source)
        missing = CONTRACT_METHODS.reject { |method| source.respond_to?(method) }
        return if missing.empty?

        raise Xbookmark::ConfigError,
              "source #{source.class} does not satisfy the bookmark-source contract (missing: #{missing.join(", ")})"
      end

      # Releases each source's resources once the run is done. The browser source
      # keeps Chromium alive across get_tweet/bookmarks calls for reuse, so the
      # single quit happens here (covers the resync path, which only calls
      # get_tweet). The API source has no #close.
      def close_sources
        @sources.each { |source| source.close if source.respond_to?(:close) }
      end
    end
  end
end
