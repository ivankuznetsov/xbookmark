---
title: Commands
type: commands
source: ../xbookmark.worktrees/i-want-to-create-a-260504-1253/bin/xbookmark; ../xbookmark.worktrees/i-want-to-create-a-260504-1253/lib/xbookmark/cli.rb; ../xbookmark.worktrees/i-want-to-create-a-260504-1253/lib/xbookmark/cli/*.rb; ../xbookmark.worktrees/i-want-to-create-a-260504-1253/lib/xbookmark/config.rb; ../xbookmark.worktrees/create-proper-readme-md-for-260513-2ba1/README.md; ../xbookmark.worktrees/create-proper-readme-md-for-260513-2ba1/.env.example
created: 2026-05-14
updated: 2026-05-14
tags: [commands, cli]
---

**TLDR**: The implementation branch exposes a Thor CLI, while the README branch now documents a richer v1 public command contract that is not yet implemented.

## Scope

Command facts here are branch-scoped. The `main` branch does not yet track `bin/xbookmark` or `lib/xbookmark/cli*.rb`.

- Implementation source is in branch `i-want-to-create-a-260504-1253`.
- README/spec source is in branch `create-proper-readme-md-for-260513-2ba1`.

## Implemented Command Surface

- `bin/xbookmark` requires `lib/xbookmark/cli` and starts `Xbookmark::CLI`.
- `xbookmark version` prints `Xbookmark::VERSION`.
- `xbookmark auth login` runs OAuth 2.0 PKCE against X and writes tokens to the configured env file.
- `xbookmark auth status` reports whether an access token is present; there is no CLI command for `refresh` or `logout` in the implementation branch.
- `xbookmark backfill [--limit N]` runs a limited test backfill when `--limit` is present and a full backfill otherwise.
- `xbookmark sync [--from-scheduler]` runs incremental sync; scheduler invocations can skip if the last completed sync is too recent.
- `xbookmark resync TWEET_ID` re-fetches and reprocesses one tweet.
- `xbookmark find QUERY [--limit N]` searches the QMD `bookmarks` collection and prints numbered text results. `Qmd::Searcher` invokes `qmd query --collection bookmarks --types lex,vec --limit N --json QUERY`.
- `xbookmark doctor` checks platform, scheduler backend, vault path, state DB path, `codex`, whisper, `qmd`, and X auth token presence.
- `xbookmark install [--time HH:MM] [--dry-run] [--uninstall]` installs or removes the daily scheduler and registers QMD when installing.

Global options visible in `Xbookmark::CLI` are `--vault` and `--verbose`.

Configuration loaded by these commands comes from `XBOOKMARK_ENV_FILE`, `$PWD/.env`, and `~/.config/xbookmark/.env`, plus process environment values. The implementation uses `XBOOKMARK_VAULT` or `--vault` for the vault path.

## Command Flow

- `backfill`, `sync`, and `resync` all load config, open the SQLite state store, create an X API client, and delegate to `Xbookmark::Sync::Runner`.
- `find` delegates to `Xbookmark::Qmd::Searcher`.
- `install` delegates to `Xbookmark::Scheduler::Factory` and `Xbookmark::Qmd::Registrar`.
- `doctor` performs local binary and auth checks without running a sync.

## README Branch Public Contract

Commit `8e6ad0e` on the README branch documents the intended public surface as:

- `bin/xbookmark auth login [--port PORT]`, `auth refresh`, `auth logout`, and read-only `auth status`.
- `bin/xbookmark backfill [--limit N] [--since YYYY-MM-DD] [--dry-run] [--overwrite]`.
- `bin/xbookmark find '<query>' [--type lex|vec|hyde] [--limit N] [--json]`, including a stable JSON result envelope.
- `bin/xbookmark enrich [--bookmark ID | --all] [--force]`.
- `bin/xbookmark schedule install --daily [--at HH:MM] [--scheduler auto|launchd|systemd|cron] [--config PATH]`, plus `schedule status` and `schedule uninstall`.
- Config resolution through `--config PATH`, `XBOOKMARK_CONFIG`, `$PWD/.env`, then `~/.config/xbookmark/.env`.
- `.env.example` keys `X_CLIENT_ID`, `X_CLIENT_SECRET`, `X_REDIRECT_URI`, `OBSIDIAN_VAULT_PATH`, `WHISPER_BACKEND`, `WHISPER_MODEL`, and `CODEX_PROFILE`.

## Known Mismatches

The README branch is ahead of the implementation branch's command surface. Differences verified in source include:

- README uses `schedule ...`; implementation exposes `install [--time] [--dry-run] [--uninstall]`.
- README uses `--config`/`XBOOKMARK_CONFIG`; implementation uses `XBOOKMARK_ENV_FILE` and has no `--config` global option.
- README uses `OBSIDIAN_VAULT_PATH`; implementation uses `XBOOKMARK_VAULT` or default XDG/macOS vault paths.
- README says `auth login --port` with port 8765 fallback behavior; implementation derives the callback port from `X_REDIRECT_URI` and defaults to `Auth::LOCAL_PORT = 7799`.
- README says tokens live in `~/.config/xbookmark/credentials.json`; implementation writes `X_ACCESS_TOKEN`, `X_REFRESH_TOKEN`, and `X_TOKEN_EXPIRES_AT` into the env file.
- README documents `auth refresh`, `auth logout`, `enrich`, `backfill --since/--dry-run/--overwrite`, `find --type`, and `find --json`; these are not implemented as CLI options or commands in the implementation branch.
- README documents cron scheduler fallback and scheduled `backfill`; implementation scheduler factory chooses systemd on Linux and launchd on macOS, and scheduler artifacts run `sync --from-scheduler`.

Record any reconciliation work in [[gaps]] before claiming the README and implementation are aligned.

Related: [[architecture]], [[api]], [[data-model]], [[dependencies]], [[gaps]].
