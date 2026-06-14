---
title: Data Model
type: data-model
source: lib/xbookmark/state/migrations.rb; lib/xbookmark/state/store.rb; lib/xbookmark/render/bookmark_renderer.rb
created: 2026-05-14
updated: 2026-06-14
tags: [data, sqlite, bookmark-wiki]
---

**TLDR**: xbookmark stores sync metadata, bookmark status, and optional aux-page summary metadata in SQLite, while final user-facing data lives as markdown and media files in a standalone bookmark wiki.

## Scope

The data model is tracked on `main`. The current SQLite schema version is 2.

## SQLite State DB

`Xbookmark::State::Migrations` creates a single schema at `<bookmark-wiki>/.xbookmark/state.db`:

- `meta(key TEXT PRIMARY KEY, value TEXT)`
- `bookmarks(tweet_id TEXT PRIMARY KEY, author_handle TEXT NOT NULL, bookmarked_at TEXT NOT NULL, ingested_at TEXT, status TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, markdown_path TEXT, enrichment_digest TEXT, payload_json TEXT)`
- `idx_bookmarks_status` on `bookmarks(status)`
- `pages(kind TEXT NOT NULL, slug TEXT NOT NULL, path TEXT NOT NULL, last_summarized_at TEXT, summary_input_digest TEXT, PRIMARY KEY(kind, slug))`

`Migrations.apply!` creates tables/indexes if missing and stamps `schema_version = 2`. Version 2 adds `bookmarks.payload_json`, which stores a minimized per-bookmark X API payload so pending and retryable rows can be enriched later without re-fetching the tweet first. The v2 migration also repairs databases that were stamped version 2 before the physical column existed.

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

Failures increment `attempts`; after three attempts or a permanent error flag, the bookmark becomes `permanent_error`. Successful processing resets attempts and clears `last_error`. Global source outages such as X auth, rate-limit, and transport failures are reported separately as `source blocked`; they do not count as per-bookmark permanent errors.

## Bookmark Wiki Layout

The renderer writes final markdown under:

```text
<bookmark-wiki>/bookmarks/YYYY/MM/DD/<tweet_id>.md
<bookmark-wiki>/media/<tweet_id>/*
<bookmark-wiki>/authors/<handle>.md
<bookmark-wiki>/topics/<slug>.md
<bookmark-wiki>/entities/<slug>.md
<bookmark-wiki>/threads/<conversation_id>.md
<bookmark-wiki>/.xbookmark/state.db
<bookmark-wiki>/.xbookmark/scratch/*
```

Bookmark markdown frontmatter includes `xbookmark_schema`, tweet and author fields, timestamps, tags, topics, entities, media records, thread, links, summary, and `enrichment_status`.

## Transactional Behavior

`Xbookmark::Sync::Pipeline` processes one bookmark in scratch space, moves media into the final bookmark wiki location, writes markdown via `AtomicWriter`, then ensures aux pages and removes scratch. Author/topic/entity aux pages always exist for backlinks, but their own LLM summaries are only generated when `XBOOKMARK_AUX_SUMMARIES` is enabled. If a transient or permanent error occurs, scratch is removed and state is updated through `Store.record_failure`. Sync runs process cached pending/retry rows before asking X for new pages, and cached rows are ordered before uncached rows so degraded source-outage runs still do local enrichable work.

Related: [[architecture]], [[commands]], [[dependencies]], [[gaps]].
