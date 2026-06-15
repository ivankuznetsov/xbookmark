# frozen_string_literal: true

require "sqlite3"
require "fileutils"
require "time"
require "json"
require_relative "migrations"

module Xbookmark
  module State
    # Single-process SQLite state store. All writes happen inside
    # transactions; concurrent processes are rejected via BEGIN IMMEDIATE.
    class Store
      STATUS_PENDING        = "pending"
      STATUS_DONE           = "done"
      STATUS_NEEDS_RETRY    = "needs_retry"
      STATUS_PERMANENT      = "permanent_error"

      MODE_FRESH             = "fresh"
      MODE_TEST_BACKFILLED   = "test_backfilled"
      MODE_FULLY_BACKFILLED  = "fully_backfilled"
      MODE_INCREMENTAL       = "incremental"

      attr_reader :path

      def initialize(path)
        @path = path
        FileUtils.mkdir_p(File.dirname(path)) unless path == ":memory:"
        @db = SQLite3::Database.new(path)
        @db.results_as_hash = true
        @db.busy_timeout = 5_000
        Migrations.apply!(@db)
        ensure_meta_defaults
      end

      def close
        @db&.close
        @db = nil
      end

      # ---- meta ----

      def get_meta(key)
        @db.get_first_value("SELECT value FROM meta WHERE key = ?", [key])
      end

      def set_meta(key, value)
        @db.execute("INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)", [key, value.nil? ? nil : value.to_s])
      end

      def mode
        get_meta("mode") || MODE_FRESH
      end

      def mode=(value)
        set_meta("mode", value)
      end

      def cursor
        get_meta("last_pagination_token")
      end

      def cursor=(value)
        set_meta("last_pagination_token", value)
      end

      def last_sync_finished_at
        ts = get_meta("last_sync_finished_at")
        ts ? Time.parse(ts) : nil
      end

      def mark_sync_finished!(time = Time.now.utc)
        set_meta("last_sync_finished_at", time.iso8601)
      end

      def mark_sync_started!(time = Time.now.utc)
        set_meta("last_sync_at", time.iso8601)
      end

      def mark_full_backfill_complete!(time = Time.now.utc)
        set_meta("last_full_backfill_at", time.iso8601)
      end

      # ---- bookmarks ----

      def find_bookmark(tweet_id)
        row = @db.get_first_row("SELECT * FROM bookmarks WHERE tweet_id = ?", [tweet_id.to_s])
        row && symbolize_keys(row)
      end

      def upsert_pending(tweet_id:, author_handle:, bookmarked_at:, payload: nil)
        payload_json = payload ? JSON.generate(payload) : nil
        @db.execute(<<~SQL, [tweet_id.to_s, author_handle.to_s, iso(bookmarked_at), STATUS_PENDING, payload_json])
          INSERT OR IGNORE INTO bookmarks(tweet_id, author_handle, bookmarked_at, status, payload_json)
          VALUES (?, ?, ?, ?, ?)
        SQL
        store_payload!(tweet_id: tweet_id, payload: payload) if payload
      end

      def record_success(tweet_id:, markdown_path:, digest:, time: Time.now.utc)
        @db.execute(<<~SQL, [iso(time), STATUS_DONE, markdown_path.to_s, digest.to_s, tweet_id.to_s])
          UPDATE bookmarks
             SET ingested_at = ?,
                 status = ?,
                 attempts = 0,
                 last_error = NULL,
                 markdown_path = ?,
                 enrichment_digest = ?
           WHERE tweet_id = ?
        SQL
      end

      def record_failure(tweet_id:, error:, permanent: false)
        status = nil
        @db.transaction do
          row = @db.get_first_row("SELECT attempts FROM bookmarks WHERE tweet_id = ?", [tweet_id.to_s])
          attempts = ((row && row["attempts"]) || 0).to_i + 1
          status = permanent || attempts >= 3 ? STATUS_PERMANENT : STATUS_NEEDS_RETRY
          @db.execute(<<~SQL, [status, attempts, error.to_s[0, 4000], tweet_id.to_s])
            UPDATE bookmarks
               SET status = ?,
                   attempts = ?,
                   last_error = ?
             WHERE tweet_id = ?
          SQL
        end
        status
      end

      # Work that can be attempted before asking X for new bookmark pages.
      # `pending` covers rows discovered before an interrupted process, while
      # `needs_retry` covers rows that failed transiently in the pipeline.
      # Cached rows come first so source-blocked scheduler runs still process
      # all locally enrichable work before any uncached row asks X for data.
      def bookmarks_to_process(limit: 100)
        @db.execute(<<~SQL, [STATUS_PENDING, STATUS_NEEDS_RETRY, limit]).map { |r| symbolize_keys(r) }
          SELECT * FROM bookmarks
           WHERE status IN (?, ?)
           ORDER BY CASE WHEN payload_json IS NULL OR payload_json = '' THEN 1 ELSE 0 END,
                    attempts ASC,
                    bookmarked_at DESC
           LIMIT ?
        SQL
      end

      def payload_for(tweet_id)
        raw = @db.get_first_value("SELECT payload_json FROM bookmarks WHERE tweet_id = ?", [tweet_id.to_s])
        return nil if raw.to_s.empty?

        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end

      def store_payload!(tweet_id:, payload:)
        return if payload.nil?

        @db.execute("UPDATE bookmarks SET payload_json = ? WHERE tweet_id = ?", [JSON.generate(payload), tweet_id.to_s])
      end

      def already_done?(tweet_id)
        row = find_bookmark(tweet_id)
        row && row[:status] == STATUS_DONE
      end

      def reset_to_pending!(tweet_id)
        # Resetting a previously-failed row needs to clear attempts too —
        # otherwise old retry counts carry over and the next failure can
        # tip the row straight into permanent_error.
        @db.execute(<<~SQL, [STATUS_PENDING, tweet_id.to_s])
          UPDATE bookmarks SET status = ?, attempts = 0, last_error = NULL WHERE tweet_id = ?
        SQL
      end

      # ---- pages ----

      def find_page(kind, slug)
        row = @db.get_first_row("SELECT * FROM pages WHERE kind = ? AND slug = ?", [kind, slug])
        row && symbolize_keys(row)
      end

      def upsert_page(kind:, slug:, path:, summary_input_digest: nil, summarized_at: nil)
        @db.execute(<<~SQL, [kind, slug, path, summary_input_digest, iso_or_nil(summarized_at)])
          INSERT INTO pages(kind, slug, path, summary_input_digest, last_summarized_at)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(kind, slug) DO UPDATE SET
            path = excluded.path,
            summary_input_digest = COALESCE(excluded.summary_input_digest, pages.summary_input_digest),
            last_summarized_at = COALESCE(excluded.last_summarized_at, pages.last_summarized_at)
        SQL
      end

      def all_topic_slugs
        @db.execute("SELECT slug FROM pages WHERE kind IN ('topic', 'entity')").map { |r| r["slug"] }
      end

      private

      def ensure_meta_defaults
        @db.execute("INSERT OR IGNORE INTO meta(key, value) VALUES ('mode', ?)", [MODE_FRESH])
      end

      def iso(value)
        return value if value.is_a?(String)
        return value.iso8601 if value.respond_to?(:iso8601)
        Time.parse(value.to_s).iso8601
      end

      def iso_or_nil(value)
        return nil if value.nil?
        iso(value)
      end

      def symbolize_keys(row)
        row.each_with_object({}) do |(k, v), acc|
          acc[k.to_sym] = v if k.is_a?(String)
        end
      end
    end
  end
end
