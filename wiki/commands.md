---
title: Commands
type: commands
source: bin/xbookmark; lib/xbookmark/cli.rb; lib/xbookmark/cli/*.rb; lib/xbookmark/config.rb; lib/xbookmark/x/auth.rb; lib/xbookmark/keystore/auth_config.rb; lib/xbookmark/keystore/resolver.rb; lib/xbookmark/qmd/registrar.rb; README.md; .env.example
created: 2026-05-14
updated: 2026-05-30
tags: [commands, cli]
---

**TLDR**: The README and implementation are aligned around the currently implemented Thor CLI: X auth, provider auth routing, backfill, sync, resync, find, doctor, install, setup, and uninstall.

## Fresh Setup Contract

The README agent prompt should only reference implemented commands. A new setup flow is:

1. Clone and `bundle install`.
2. Copy `.env.example` to `.env`.
3. Fill `X_CLIENT_ID`, `X_USER_ID`, optional `X_CLIENT_SECRET`, `X_REDIRECT_URI`, and `XBOOKMARK_WIKI_PATH`.
4. Run `bin/xbookmark auth login`.
5. Run `bin/xbookmark install` to install the daily scheduler and, on Linux, enable systemd linger when possible.
6. Verify with `bin/xbookmark --version` and `bin/xbookmark auth status`.

The runtime bookmark wiki created at `XBOOKMARK_WIKI_PATH` is separate from this repository's project LLM wiki in `wiki/`.

Packaged binary installs also support running `xbookmark` with no arguments in a TTY. That first-run path launches `xbookmark setup`, writes required X credentials into the keystore when available, removes stale invalid top-level Codex `service_tier` values, and installs the daily scheduler.

## Implemented Command Surface

- `bin/xbookmark` requires `lib/xbookmark/cli` and starts `Xbookmark::CLI`.
- `xbookmark version` prints `Xbookmark::VERSION`.
- `xbookmark auth login` runs OAuth 2.0 PKCE against X and writes tokens to the loaded env file when one is active, to the stable user env file when keychain is the only automatic store, or to the active keystore backend otherwise.
- `xbookmark auth login PROVIDER` prompts for a third-party provider key without echoing input, writes it to the platform keychain backend, and records keychain routing in `auth.toml`.
- `xbookmark auth bind PROVIDER OP_REF` records a 1Password `op://` reference in `auth.toml` and smoke-checks it immediately when the `op` CLI is available.
- `xbookmark auth list` shows configured provider names and backends without printing secret values.
- `xbookmark auth show PROVIDER` resolves and prints a provider credential for diagnostics and scripts.
- `xbookmark auth rm PROVIDER` removes the provider from `auth.toml` and deletes the keychain entry when that provider was routed to `keychain`.
- `xbookmark auth status` reports whether an access token is present.
- `xbookmark backfill [--limit N]` runs a limited test backfill when `--limit` is present and a full backfill otherwise.
- `xbookmark sync [--from-scheduler]` runs incremental sync; scheduler invocations can skip if the last completed sync is too recent.
- `xbookmark resync TWEET_ID` re-fetches and reprocesses one tweet.
- `xbookmark find QUERY [--limit N]` searches the QMD `bookmarks` collection and prints numbered text results. `Qmd::Searcher` invokes `qmd query --collection bookmarks --types lex,vec --limit N --json QUERY` and caps parsed results to `N` even if the installed QMD returns extra hits.
- `xbookmark doctor` checks platform, scheduler backend, bookmark wiki path, state DB path, `codex`, whisper, `qmd`, and X auth token presence.
- `xbookmark install [--time HH:MM] [--dry-run] [--uninstall]` installs or removes the daily scheduler and registers QMD when installing. Non-dry-run installs also remove stale invalid top-level Codex `service_tier` values before writing scheduler state, but cleanup failures are warnings. Linux installs try to enable systemd linger so the timer can fire after logout.
- `xbookmark setup` is the interactive first-run wizard. It imports legacy env-file credentials into the active keystore, prompts for missing X keys, removes stale invalid Codex `service_tier` values, and installs the scheduler. Service-tier cleanup and scheduler failures are reported but do not abort the wizard.
- `xbookmark uninstall --purge [--yes] [--dry-run]` removes scheduler units, keystore entries, and the config directory after explicit purge confirmation.

Global options visible in `Xbookmark::CLI` are `--wiki`, `--vault` as a legacy alias, and `--verbose`.

Configuration loaded by these commands comes from `XBOOKMARK_ENV_FILE`, `$PWD/.env`, and `~/.config/xbookmark/.env`, plus process environment values. The preferred bookmark wiki path key is `XBOOKMARK_WIKI_PATH`; `XBOOKMARK_VAULT`, `OBSIDIAN_VAULT_PATH`, and `--vault` are compatibility aliases.

Provider credential resolution uses `Xbookmark::Keystore::Resolver`: CI or `XBOOKMARK_KEYS_FROM_ENV=1` forces environment lookup, `auth.toml` can route providers to 1Password or the platform keychain, and plain environment variables are the final non-CI fallback.

## Command Flow

- `backfill`, `sync`, and `resync` all load config, open the SQLite state store, create an X API client, and delegate to `Xbookmark::Sync::Runner`.
- `sync` starts from the newest bookmark page and stops after a page with no new bookmarks; X `next_token` values are not treated as durable cursors between runs.
- `find` delegates to `Xbookmark::Qmd::Searcher`.
- `auth login PROVIDER`, `auth bind`, `auth list`, `auth show`, and `auth rm` delegate to `Xbookmark::Keystore::AuthConfig`, `Resolver`, and the selected platform/1Password backend.
- `install` delegates to `Xbookmark::Scheduler::Factory` and, when installing for real, `Xbookmark::CodexConfig` and `Xbookmark::Qmd::Registrar`; `--dry-run` and `--uninstall` do not register QMD or change Codex config.
- `Xbookmark::Scheduler::Systemd` writes and enables the user timer, then runs `loginctl enable-linger <user>` when linger is not already enabled; failure is non-fatal and prints the manual command.
- The registrar supports current QMD `collection list`/`collection add` command shapes and legacy `list`/`register`/`index` fallbacks, with `qmd update` as the final legacy indexing fallback.
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
