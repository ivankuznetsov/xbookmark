---
title: Commands
type: commands
source: ../xbookmark.worktrees/i-want-to-create-a-260504-1253/lib/xbookmark/cli.rb; ../xbookmark.worktrees/i-want-to-create-a-260504-1253/lib/xbookmark/cli/*.rb; ../xbookmark.worktrees/create-proper-readme-md-for-260513-2ba1/README.md
created: 2026-05-14
updated: 2026-05-14
tags: [commands, cli]
---

**TLDR**: The unmerged implementation branch exposes a Thor CLI for auth, backfill, sync, resync, search, diagnostics, and scheduler install.

## Scope

Command facts here are branch-scoped to `i-want-to-create-a-260504-1253`. The `main` branch does not yet track `bin/xbookmark` or `lib/xbookmark/cli*.rb`.

## Implemented Command Surface

- `xbookmark version` prints `Xbookmark::VERSION`.
- `xbookmark auth login` runs OAuth 2.0 PKCE against X and writes tokens to the configured env file.
- `xbookmark auth status` reports whether an access token is present.
- `xbookmark backfill [--limit N]` runs a limited test backfill when `--limit` is present and a full backfill otherwise.
- `xbookmark sync [--from-scheduler]` runs incremental sync; scheduler invocations can skip if the last completed sync is too recent.
- `xbookmark resync TWEET_ID` re-fetches and reprocesses one tweet.
- `xbookmark find QUERY [--limit N]` searches the QMD `bookmarks` collection.
- `xbookmark doctor` checks platform, scheduler backend, vault path, state DB path, `codex`, whisper, `qmd`, and X auth token presence.
- `xbookmark install [--time HH:MM] [--dry-run] [--uninstall]` installs or removes the daily scheduler and registers QMD when installing.

Global options visible in `Xbookmark::CLI` are `--vault` and `--verbose`.

## Command Flow

- `backfill`, `sync`, and `resync` all load config, open the SQLite state store, create an X API client, and delegate to `Xbookmark::Sync::Runner`.
- `find` delegates to `Xbookmark::Qmd::Searcher`.
- `install` delegates to `Xbookmark::Scheduler::Factory` and `Xbookmark::Qmd::Registrar`.
- `doctor` performs local binary and auth checks without running a sync.

## README Branch Mismatch

The README review branch documents additional or different public CLI details, including `schedule install/uninstall`, `enrich`, `auth logout`, `auth status` auto-refresh behavior, JSON find output, and config keys such as `OBSIDIAN_VAULT_PATH`. Those are not all visible in the implementation branch command files read during this refresh.

Record any reconciliation work in [[gaps]] before claiming the README and implementation are aligned.

Related: [[architecture]], [[data-model]], [[dependencies]], [[gaps]].
