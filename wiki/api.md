---
title: API Surface
type: api
source: lib/xbookmark/x/auth.rb; lib/xbookmark/x/client.rb; lib/xbookmark/qmd/registrar.rb; lib/xbookmark/qmd/searcher.rb; lib/xbookmark/cli/auth.rb; lib/xbookmark/keystore/auth_config.rb; lib/xbookmark/keystore/resolver.rb; lib/xbookmark/keystore/one_password.rb; README.md; .env.example
created: 2026-05-14
updated: 2026-06-06
tags: [api, x-api, oauth, cli]
---

**TLDR**: `xbookmark` has no web app routes; its external surface is a CLI, X API v2 calls, a temporary local OAuth callback, QMD/Codex subprocess calls, and local auth-routing config.

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
- Tokens are persisted by updating the loaded env file with `0600` permissions when one is active. Without a loaded env file, token writes go to the active keystore backend except for the macOS keychain path, where rotating OAuth tokens stay in the stable user env file because the `security` CLI accepts generic-password values as argv.

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

## Codex Config File Surface

- `Xbookmark::CodexConfig.default_path` reads `$CODEX_HOME/config.toml` when `CODEX_HOME` is set, otherwise `~/.codex/config.toml`.
- `xbookmark setup` and non-dry-run `xbookmark install` remove only stale invalid top-level `service_tier` values before the first TOML table. Project-scoped tables such as `[projects."/tmp/app"]` and valid speed modes are preserved.
- When the file is rewritten, xbookmark creates parent directories as needed, writes through an atomic temp-file replacement, and sets the config file mode to `0600`.

## Auth Routing Config Surface

- `Xbookmark::Keystore::AuthConfig.default_path` is `Xbookmark::Paths.default_config_dir/auth.toml`, normally `~/.config/xbookmark/auth.toml`.
- The TOML file records provider backend routing, not secret values. Supported backend strings in the class are `keychain` and `1password`.
- Provider names are normalized through `Xbookmark::Keystore::Provider.parse`; `AuthConfig` also drops hand-edited TOML sections whose names do not match the shared `Provider::NAME_PATTERN` (`/\A[a-z0-9_-]+\z/`) so invalid quoted/dotted section names are not reserialized into unparseable bare section headers.
- 1Password entries must use an `op://` reference. The actual secret is read later by the `op` CLI backend.
- Provider auth routing is public through `xbookmark auth login PROVIDER`, `xbookmark auth bind PROVIDER OP_REF`, `xbookmark auth list`, `xbookmark auth show PROVIDER`, and `xbookmark auth rm PROVIDER`.
- `Xbookmark::Keystore::Resolver` resolves provider credentials in this order: exact `CI=true` or `XBOOKMARK_KEYS_FROM_ENV=1` env-forced lookup, `auth.toml` routing to 1Password or the platform keychain, normal environment fallback, then an actionable error. The CI/env-forced branch is mutually exclusive: it skips `auth.toml` entirely and fails if the canonical or legacy env key is absent.
- On Linux, routed platform-keychain provider lookups require both `secret-tool` and a D-Bus session (`DBUS_SESSION_BUS_ADDRESS`); otherwise the resolver raises the same actionable keychain-unavailable message used for a missing `secret-tool` instead of allowing raw backend stderr to escape.
- `auth show PROVIDER` prints the resolved credential for diagnostics and scripts, so it is intentionally more sensitive than `auth list`, which never prints secret values.

## Public Contract Notes

The current README documents the current CLI only. Deferred commands and flags are cataloged in [[commands]] so they are not accidentally exposed in setup docs before implementation.

Related: [[commands]], [[architecture]], [[dependencies]], [[gaps]].
