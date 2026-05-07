# frozen_string_literal: true

module Xbookmark
  module State
    module Migrations
      CURRENT_VERSION = 1

      SCHEMA = <<~SQL
        CREATE TABLE IF NOT EXISTS meta (
          key TEXT PRIMARY KEY,
          value TEXT
        );

        CREATE TABLE IF NOT EXISTS bookmarks (
          tweet_id TEXT PRIMARY KEY,
          author_handle TEXT NOT NULL,
          bookmarked_at TEXT NOT NULL,
          ingested_at TEXT,
          status TEXT NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0,
          last_error TEXT,
          markdown_path TEXT,
          enrichment_digest TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_bookmarks_status ON bookmarks(status);

        CREATE TABLE IF NOT EXISTS pages (
          kind TEXT NOT NULL,
          slug TEXT NOT NULL,
          path TEXT NOT NULL,
          last_summarized_at TEXT,
          summary_input_digest TEXT,
          PRIMARY KEY (kind, slug)
        );
      SQL

      module_function

      def apply!(db)
        db.execute_batch(SCHEMA)
        current = current_version(db)
        return if current >= CURRENT_VERSION
        db.execute("INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)", ["schema_version", CURRENT_VERSION.to_s])
      end

      def current_version(db)
        row = db.get_first_value("SELECT value FROM meta WHERE key = 'schema_version'")
        row.to_i
      rescue StandardError
        0
      end
    end
  end
end
