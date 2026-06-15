# frozen_string_literal: true

module Xbookmark
  module State
    # Schema bootstrap for the SQLite state DB. `apply!` creates the
    # current schema when needed, then runs explicit per-version migration
    # steps for existing databases.
    module Migrations
      CURRENT_VERSION = 3

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
          enrichment_digest TEXT,
          payload_json TEXT
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

        CREATE TABLE IF NOT EXISTS concepts (
          slug TEXT PRIMARY KEY,
          label TEXT NOT NULL,
          kind TEXT NOT NULL,
          aliases_json TEXT NOT NULL DEFAULT '[]',
          broader_json TEXT NOT NULL DEFAULT '[]',
          facets_json TEXT NOT NULL DEFAULT '[]',
          evidence_count INTEGER NOT NULL DEFAULT 0,
          confidence REAL NOT NULL DEFAULT 0.0,
          curator_outcome TEXT NOT NULL DEFAULT 'canonical',
          updated_at TEXT
        );

        CREATE TABLE IF NOT EXISTS curator_decisions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          slug TEXT NOT NULL,
          decision_json TEXT NOT NULL,
          created_at TEXT NOT NULL
        );
      SQL

      module_function

      def apply!(db)
        db.execute_batch(SCHEMA)
        current = current_version(db)
        migrate_to_v2(db) if current < 2 || !column_exists?(db, "bookmarks", "payload_json")
        migrate_to_v3(db) if current < 3
        return if current >= CURRENT_VERSION
        db.execute("INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)", ["schema_version", CURRENT_VERSION.to_s])
      end

      def current_version(db)
        row = db.get_first_value("SELECT value FROM meta WHERE key = 'schema_version'")
        row.to_i
      rescue StandardError
        0
      end

      def migrate_to_v2(db)
        return if column_exists?(db, "bookmarks", "payload_json")

        db.execute("ALTER TABLE bookmarks ADD COLUMN payload_json TEXT")
      end

      def migrate_to_v3(db)
        db.execute_batch(SCHEMA)
        db.execute(<<~SQL)
          INSERT OR IGNORE INTO concepts(slug, label, kind, evidence_count, confidence, curator_outcome)
          SELECT slug, slug, kind, 1, 0.1, 'canonical'
            FROM pages
           WHERE kind IN ('topic', 'entity')
        SQL
      end

      def column_exists?(db, table, column)
        db.execute("PRAGMA table_info(#{table})").any? { |row| row["name"] == column || row[1] == column }
      end
    end
  end
end
