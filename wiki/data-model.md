---
title: Data Model
type: data-model
source: lib/xbookmark/state/migrations.rb; lib/xbookmark/state/store.rb; lib/xbookmark/render/bookmark_renderer.rb
created: 2026-05-14
updated: 2026-06-15
tags: [data, sqlite, bookmark-wiki]
---

**TLDR**: xbookmark stores sync metadata, bookmark status, concept metadata, and optional aux-page summary metadata in SQLite, while final user-facing data lives as markdown and media files in a standalone bookmark wiki.

## Scope

The data model is tracked on `main`. The current SQLite schema version is 3.

## SQLite State DB

`Xbookmark::State::Migrations` creates a single schema at `<bookmark-wiki>/.xbookmark/state.db`:

- `meta(key TEXT PRIMARY KEY, value TEXT)`
- `bookmarks(tweet_id TEXT PRIMARY KEY, author_handle TEXT NOT NULL, bookmarked_at TEXT NOT NULL, ingested_at TEXT, status TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, markdown_path TEXT, enrichment_digest TEXT, payload_json TEXT)`
- `idx_bookmarks_status` on `bookmarks(status)`
- `pages(kind TEXT NOT NULL, slug TEXT NOT NULL, path TEXT NOT NULL, last_summarized_at TEXT, summary_input_digest TEXT, PRIMARY KEY(kind, slug))`
- `concepts(slug TEXT PRIMARY KEY, label TEXT NOT NULL, kind TEXT NOT NULL, aliases_json TEXT NOT NULL DEFAULT '[]', broader_json TEXT NOT NULL DEFAULT '[]', facets_json TEXT NOT NULL DEFAULT '[]', evidence_count INTEGER NOT NULL DEFAULT 0, confidence REAL NOT NULL DEFAULT 0.0, curator_outcome TEXT NOT NULL DEFAULT 'canonical', updated_at TEXT)`
- `curator_decisions(id INTEGER PRIMARY KEY AUTOINCREMENT, slug TEXT NOT NULL, decision_json TEXT NOT NULL, created_at TEXT NOT NULL)`

`Migrations.apply!` creates tables/indexes if missing and stamps `schema_version = 3`. Version 2 adds `bookmarks.payload_json`, which stores a minimized per-bookmark X API payload so pending and retryable rows can be enriched later without re-fetching the tweet first. The v2 migration also repairs databases that were stamped version 2 before the physical column existed. Version 3 adds concept metadata and seeds concept rows from existing legacy topic/entity page rows.

## Status and Mode Values

Bookmark status constants in `Xbookmark::State::Store`:

- `pending`
- `done`
- `needs_retry`
- `permanent_error`

Sync mode constants:

- `fresh`
- `test_backfilled`
- `fully_backfilled`
- `incremental`

Failures increment `attempts`; after three attempts or a permanent error flag, the bookmark becomes `permanent_error`. `Store.record_failure` returns the final stored status so the sync report can distinguish rows that remain retryable from rows promoted to permanent during the current run. Successful processing resets attempts and clears `last_error`. Global source outages such as X auth, rate-limit, and transport failures are reported separately as `source blocked`; they do not count as per-bookmark permanent errors.

## Bookmark Wiki Layout

The renderer writes final markdown under:

```text
<bookmark-wiki>/bookmarks/YYYY/MM/DD/<readable-slug>-<tweet_id>.md
<bookmark-wiki>/media/<tweet_id>/*
<bookmark-wiki>/authors/<handle>.md
<bookmark-wiki>/concepts/<slug>.md
<bookmark-wiki>/concepts/index.md
<bookmark-wiki>/threads/<readable-thread-slug>.md
<bookmark-wiki>/.xbookmark/state.db
<bookmark-wiki>/.xbookmark/scratch/*
<bookmark-wiki>/.xbookmark/taxonomy-*.manifest.json
<bookmark-wiki>/.xbookmark/taxonomy-*.graph-health.json
```

Bookmark markdown frontmatter includes `xbookmark_schema`, tweet and author fields, timestamps, sanitized tags, canonical concept slugs/labels, facet tags, media records, conversation/thread references, links, summary, and `enrichment_status`.

Concept pages include `kind: concept`, `slug`, `label`, `concept_kind`, `aliases`, `broader`, `tags`, `evidence_count`, `confidence`, and `curator_outcome`. `broader` relationships are also rendered as wikilinks so Obsidian graph edges show hierarchy.

## Transactional Behavior

`Xbookmark::Sync::Pipeline` processes one bookmark in scratch space, moves media into the final bookmark wiki location, writes markdown via `AtomicWriter`, then ensures author/concept/thread pages and removes scratch. Author aux summaries are only generated when `XBOOKMARK_AUX_SUMMARIES` is enabled. Singleton conversations do not create thread pages; `Xbookmark::Sync::ThreadIndex` creates readable thread pages only when local state proves a real multi-bookmark conversation. If a transient or permanent error occurs, scratch is removed and state is updated through `Store.record_failure`. Sync runs process cached pending/retry rows before asking X for new pages, and cached rows are ordered before uncached rows so degraded source-outage runs still do local enrichable work.

Taxonomy rebuilds are local data migrations. `xbookmark taxonomy rebuild --apply` writes a pre-apply snapshot and manifest under `.xbookmark`, renames numeric source notes, prunes generated numeric singleton thread pages, updates `bookmarks.markdown_path` through a path-only store method, writes a graph-health report, and reindexes QMD. Dry-run/audit reports use explicit states: `clean`, `proposed_changes`, `blocked_conflicts`, `applied`, and `partial_failure`.

Related: [[architecture]], [[commands]], [[dependencies]], [[gaps]].
