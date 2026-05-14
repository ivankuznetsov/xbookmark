---
title: API Surface
type: api
source: ../xbookmark.worktrees/i-want-to-create-a-260504-1253/lib/xbookmark/x/auth.rb; ../xbookmark.worktrees/i-want-to-create-a-260504-1253/lib/xbookmark/x/client.rb; ../xbookmark.worktrees/i-want-to-create-a-260504-1253/lib/xbookmark/qmd/searcher.rb; ../xbookmark.worktrees/create-proper-readme-md-for-260513-2ba1/README.md; ../xbookmark.worktrees/create-proper-readme-md-for-260513-2ba1/.env.example
created: 2026-05-14
updated: 2026-05-14
tags: [api, x-api, oauth, cli]
---

**TLDR**: `xbookmark` has no web app routes; its external surface is a CLI, X API v2 calls, a temporary local OAuth callback, QMD subprocess calls, and README-documented output contracts.

## Scope

API facts are branch-scoped until implementation and README branches are reconciled:

- Runtime source read from branch `i-want-to-create-a-260504-1253`.
- README/spec source read from branch `create-proper-readme-md-for-260513-2ba1`.
- `main` does not currently track application routes, handlers, API specs, or runtime source.

## HTTP Routes

There is no persistent HTTP server or application route table in the implementation branch.

During `auth login`, `Xbookmark::X::Auth` starts a temporary WEBrick loopback server and mounts only `/callback`. The callback accepts the OAuth authorization code, validates the `state` parameter, and then shuts the server down.

## X OAuth Surface

Implementation branch:

- Authorization URL: `https://twitter.com/i/oauth2/authorize`.
- Token URL: `https://api.twitter.com/2/oauth2/token`.
- Scopes: `tweet.read`, `users.read`, `bookmark.read`, and `offline.access`.
- PKCE method: S256.
- Default callback URI is built from `Xbookmark::X::Auth::LOCAL_PORT`, which is `7799` in the implementation branch.
- Refresh is implemented in `Xbookmark::X::Auth#refresh!`, but no `xbookmark auth refresh` CLI command exists yet.
- Tokens are persisted by updating the configured env file with `0600` permissions.

README branch:

- Documents default callback `http://127.0.0.1:8765/callback`.
- Documents `auth login --port PORT`, automatic fallback through port `8800`, explicit `auth refresh`, and credentials at `~/.config/xbookmark/credentials.json`.

These README details are not yet backed by the implementation source read during this refresh.

## X API Client Surface

`Xbookmark::X::Client` calls X API v2 through Faraday:

- `GET /2/users/:user_id/bookmarks` for bookmark pages.
- `GET /2/tweets/:id` for a single tweet.
- `GET /2/tweets/search/recent` with `conversation_id:<id>` for conversation context.

Requests include tweet, user, media, and expansion fields defined in `Xbookmark::X::Client`. The client retries selected 5xx responses through Faraday, refreshes once on 401 when a refresh token is present, raises `RateLimited` on 429, and raises transient errors for other non-success responses.

## QMD Search Surface

Implementation branch:

- Collection name is `bookmarks`.
- `Qmd::Searcher` invokes `qmd query --collection bookmarks --types lex,vec --limit N --json QUERY`.
- The CLI currently prints numbered text results with score, path, and optional snippet.

README branch:

- Documents `find --type lex|vec|hyde`.
- Documents `find --json` as a stable envelope containing query metadata and per-result fields such as `bookmark_id`, `author`, `url`, `bookmarked_at`, `title`, and `snippet`.

The JSON envelope and search-type switch are README contracts, not implementation facts yet.

## Public Contract Notes

The committed README also documents scheduled jobs, config discovery, vault path conventions, and command names. Those are cataloged in [[commands]] because they are CLI API surface.

Related: [[commands]], [[architecture]], [[dependencies]], [[gaps]].
