---
title: Commands
type: commands
source: bin/xbookmark; lib/xbookmark/cli.rb; lib/xbookmark/cli/*.rb; lib/xbookmark/config.rb; README.md; .env.example
created: 2026-05-14
updated: 2026-05-22
tags: [commands, cli]
---

**TLDR**: The README and implementation are aligned around the currently implemented Thor CLI: auth login/status, backfill, sync, resync, find, doctor, and install.

## Fresh Setup Contract

The README agent prompt should only reference implemented commands. A new setup flow is:

1. Clone and `bundle install`.
2. Copy `.env.example` to `.env`.
3. Fill `X_CLIENT_ID`, `X_USER_ID`, optional `X_CLIENT_SECRET`, `X_REDIRECT_URI`, and `XBOOKMARK_WIKI_PATH`.
4. Run `bin/xbookmark auth login`.
5. Optionally run `bin/xbookmark install` to install the daily scheduler.
6. Verify with `bin/xbookmark --version` and `bin/xbookmark auth status`.

The runtime bookmark wiki created at `XBOOKMARK_WIKI_PATH` is separate from this repository's project LLM wiki in `wiki/`.

## Implemented Command Surface

- `bin/xbookmark` requires `lib/xbookmark/cli` and starts `Xbookmark::CLI`.
- `xbookmark version` prints `Xbookmark::VERSION`.
- `xbookmark auth login` runs OAuth 2.0 PKCE against X and writes tokens to the configured env file.
- `xbookmark auth status` reports whether an access token is present.
- `xbookmark backfill [--limit N]` runs a limited test backfill when `--limit` is present and a full backfill otherwise.
- `xbookmark sync [--from-scheduler]` runs incremental sync; scheduler invocations can skip if the last completed sync is too recent.
- `xbookmark resync TWEET_ID` re-fetches and reprocesses one tweet.
- `xbookmark find QUERY [--limit N]` searches the QMD `bookmarks` collection and prints numbered text results. `Qmd::Searcher` invokes `qmd query --collection bookmarks --types lex,vec --limit N --json QUERY`.
- `xbookmark doctor` checks platform, scheduler backend, bookmark wiki path, state DB path, `codex`, whisper, `qmd`, and X auth token presence.
- `xbookmark install [--time HH:MM] [--dry-run] [--uninstall]` installs or removes the daily scheduler and registers QMD when installing.

Global options visible in `Xbookmark::CLI` are `--wiki`, `--vault` as a legacy alias, and `--verbose`.

Configuration loaded by these commands comes from `XBOOKMARK_ENV_FILE`, `$PWD/.env`, and `~/.config/xbookmark/.env`, plus process environment values. The preferred bookmark wiki path key is `XBOOKMARK_WIKI_PATH`; `XBOOKMARK_VAULT`, `OBSIDIAN_VAULT_PATH`, and `--vault` are compatibility aliases.

## Command Flow

- `backfill`, `sync`, and `resync` all load config, open the SQLite state store, create an X API client, and delegate to `Xbookmark::Sync::Runner`.
- `find` delegates to `Xbookmark::Qmd::Searcher`.
- `install` delegates to `Xbookmark::Scheduler::Factory` and `Xbookmark::Qmd::Registrar`.
- `doctor` performs local binary and auth checks without running a sync.

## Deferred Public Surface

Do not document these commands as available until implementation lands:

- `auth refresh`
- `auth logout`
- `enrich`
- `schedule install/status/uninstall`
- `backfill --since`, `--dry-run`, or `--overwrite`
- `find --type` or `--json`
- global `--config` or `XBOOKMARK_CONFIG`

Related: [[architecture]], [[api]], [[data-model]], [[dependencies]], [[gaps]].
