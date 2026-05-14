---
title: Data Model
type: data-model
source: ../xbookmark.worktrees/i-want-to-create-a-260504-1253/lib/xbookmark/state/migrations.rb; ../xbookmark.worktrees/i-want-to-create-a-260504-1253/lib/xbookmark/state/store.rb; ../xbookmark.worktrees/i-want-to-create-a-260504-1253/lib/xbookmark/render/bookmark_renderer.rb
created: 2026-05-14
updated: 2026-05-14
tags: [data, sqlite, vault]
---

**TLDR**: The implementation branch stores sync metadata, bookmark status, and aux-page summaries in SQLite, while final user-facing data lives as markdown and media files in a local vault.

## Scope

The data model is branch-scoped to `i-want-to-create-a-260504-1253`. The `main` branch does not yet track this runtime code or schema.

## SQLite State DB

`Xbookmark::State::Migrations` creates a single schema at `<vault>/.xbookmark/state.db`:

- `meta(key TEXT PRIMARY KEY, value TEXT)`
- `bookmarks(tweet_id TEXT PRIMARY KEY, author_handle TEXT NOT NULL, bookmarked_at TEXT NOT NULL, ingested_at TEXT, status TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, markdown_path TEXT, enrichment_digest TEXT)`
- `idx_bookmarks_status` on `bookmarks(status)`
- `pages(kind TEXT NOT NULL, slug TEXT NOT NULL, path TEXT NOT NULL, last_summarized_at TEXT, summary_input_digest TEXT, PRIMARY KEY(kind, slug))`

`Migrations.apply!` creates tables/indexes if missing and stamps `schema_version = 1`. Comments in the source explicitly say this is not yet a full migration framework.

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

Failures increment `attempts`; after three attempts or a permanent error flag, the bookmark becomes `permanent_error`. Successful processing resets attempts and clears `last_error`.

## Vault Layout

The renderer writes final markdown under:

```text
<vault>/bookmarks/YYYY/MM/DD/<tweet_id>.md
<vault>/media/<tweet_id>/*
<vault>/authors/<handle>.md
<vault>/topics/<slug>.md
<vault>/entities/<slug>.md
<vault>/threads/<conversation_id>.md
<vault>/.xbookmark/state.db
<vault>/.xbookmark/scratch/*
```

Bookmark markdown frontmatter includes `xbookmark_schema`, tweet and author fields, timestamps, tags, topics, entities, media records, thread, links, summary, and `enrichment_status`.

## Transactional Behavior

`Xbookmark::Sync::Pipeline` processes one bookmark in scratch space, moves media into the final vault location, writes markdown via `AtomicWriter`, then ensures aux pages and removes scratch. If a transient or permanent error occurs, scratch is removed and state is updated through `Store.record_failure`.

Related: [[architecture]], [[commands]], [[dependencies]], [[gaps]].
