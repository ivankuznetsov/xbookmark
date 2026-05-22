---
title: API Surface
type: api
source: lib/xbookmark/x/auth.rb; lib/xbookmark/x/client.rb; lib/xbookmark/qmd/registrar.rb; lib/xbookmark/qmd/searcher.rb; README.md; .env.example
created: 2026-05-14
updated: 2026-05-22
tags: [api, x-api, oauth, cli]
---

**TLDR**: `xbookmark` has no web app routes; its external surface is a CLI, X API v2 calls, a temporary local OAuth callback, and QMD registration/search subprocess calls.

## Scope

API facts are taken from the current branch and its README.

## HTTP Routes

There is no persistent HTTP server or application route table.

During `auth login`, `Xbookmark::X::Auth` starts a temporary WEBrick loopback server and mounts only `/callback`. The callback accepts the OAuth authorization code, validates the `state` parameter, and then shuts the server down.

## X OAuth Surface

- Authorization URL: `https://twitter.com/i/oauth2/authorize`.
- Token URL: `https://api.twitter.com/2/oauth2/token`.
- Scopes: `tweet.read`, `users.read`, `bookmark.read`, and `offline.access`.
- PKCE method: S256.
- The callback URI comes from `X_REDIRECT_URI`; `.env.example` uses `http://127.0.0.1:8765/callback`. If the env key is omitted, config falls back to the internal local port default.
- Refresh is implemented in `Xbookmark::X::Auth#refresh!` for the API client, but no `xbookmark auth refresh` CLI command exists yet.
- Tokens are persisted by updating the configured env file with `0600` permissions.

## X API Client Surface

`Xbookmark::X::Client` calls X API v2 through Faraday:

- `GET /2/users/:user_id/bookmarks` for bookmark pages.
- `GET /2/tweets/:id` for a single tweet.
- `GET /2/tweets/search/recent` with `conversation_id:<id>` for conversation context.

Bookmark requests use 50-item pages and follow `meta.next_token`. Production testing on 2026-05-22 found that `max_results=100` returned only 98 IDs and no `next_token`, while `max_results=50` returned 4,745 unique IDs over 95 pages. Pagination tokens are used only within one traversal; incremental sync starts at the newest page and stops after reaching a page with no new bookmarks. Requests include tweet, user, media, and expansion fields defined in `Xbookmark::X::Client`. The client retries selected 5xx responses through Faraday, refreshes once on 401 when a refresh token is present, raises `RateLimited` on 429, and raises transient errors for other non-success responses.

## QMD Subprocess Surface

- Collection name is `bookmarks`.
- `Qmd::Registrar#registered?` invokes `qmd collection list` first and falls back to legacy `qmd list`.
- `Qmd::Registrar#register!` creates `<bookmark-wiki>/bookmarks`, invokes `qmd collection add <path> --name bookmarks`, and treats that current command as already indexed.
- If the current registration command fails, the registrar falls back to legacy `qmd register --name bookmarks --path <path>` and then indexes with `qmd index --collection bookmarks`.
- If legacy indexing fails, the registrar falls back once more to `qmd update` before warning.
- `Qmd::Searcher` invokes `qmd query --collection bookmarks --types lex,vec --limit N --json QUERY`.
- The CLI currently prints numbered text results with score, path, and optional snippet.

## Codex Subprocess Surface

- `Enrich::Codex` invokes `codex exec --json` and parses JSONL event streams.
- Current Codex emits final model text under `item.completed` events with an `item.type` of `agent_message`; xbookmark unwraps the nested `item.text` JSON.
- Older model-message and plain JSON object output shapes remain accepted.

## Public Contract Notes

The committed README documents the current CLI only. Deferred commands and flags are cataloged in [[commands]] so they are not accidentally exposed in setup docs before implementation.

Related: [[commands]], [[architecture]], [[dependencies]], [[gaps]].
