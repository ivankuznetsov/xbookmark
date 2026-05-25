---
title: Dependencies
type: dependencies
source: git ls-files; Gemfile; xbookmark.gemspec; README.md
created: 2026-05-14
updated: 2026-05-25
tags: [dependencies]
---

**TLDR**: `xbookmark` is a Ruby gem-style CLI with Ruby gems for CLI/config/state/HTTP and external tools for Codex, QMD, Whisper, and native schedulers.

## Ruby Dependencies

The project contains:

- `Gemfile` using `gemspec`, plus development/test gems `rspec`, `webmock`, and `rake`.
- `xbookmark.gemspec` with runtime dependencies:
  - `thor` for the CLI.
  - `dotenv` for env-file loading.
  - `sqlite3` for local state.
  - `faraday` and `faraday-retry` for X API and link fetching.
  - `oauth2` and `webrick` for OAuth 2.0 PKCE login.
  - `nokogiri` for external link text extraction.
  - `down` for media downloads.
  - `json-schema` for validating Codex JSON output.
  - `base64` and `ostruct`.
- Required Ruby version in the gemspec is `>= 3.1`.

## External Runtime Tools

The runtime shells out to external tools:

- `codex` for LLM enrichment via `codex exec --json`.
  - Bookmark-note enrichment always uses Codex. Separate author/topic/entity page summaries are opt-in with `XBOOKMARK_AUX_SUMMARIES=true` because they add many extra Codex calls during backfill.
  - Setup/install cleanup edits `~/.codex/config.toml` or `$CODEX_HOME/config.toml` only to remove stale invalid top-level `service_tier` values that can break scheduled runs; valid speed modes are preserved.
- `qmd` for search collection registration, indexing, and querying.
- A whisper backend, detected from `WHISPER_BIN` or PATH candidates `whisper-cli`, `whisper-cpp`, `whisper`, and `faster-whisper`.
  - For whisper.cpp binaries, model aliases such as `base.en` resolve to `ggml-base.en.bin` under `WHISPER_MODEL_DIR`, the source checkout's `models/` directory next to the binary, or `./models`.
  - `ffmpeg` is required to extract audio from downloaded video media before whisper.cpp transcription.
  - `WHISPER_THREADS` optionally controls whisper.cpp CPU threads; blank defaults to up to 8 local CPU threads.
- System scheduler tools: `systemctl --user` and `loginctl` on Linux, and `launchctl` on macOS.

## External Services

- X API v2 for bookmarks and tweet details.
- Local OAuth callback server on loopback for PKCE login.
- Optional HTTP fetching of public external article links found in bookmarks, guarded by URL/IP safety checks.

## Contributor Checks

xbookmark mirrors Hive's baseline CI shape:

- `bundle exec rake coverage`
- `bundle exec rubocop --parallel --format github`
- `bundle exec brakeman --force --no-pager --quiet --format github --ignore-config config/brakeman.ignore`
- `bundle exec bundler-audit check --update`

The `coverage` rake task uses Ruby's built-in `Coverage` API to enforce 100%
line coverage for `bin/` and `lib/` without adding a new gem dependency.

The development/test bundle includes `rspec`, `webmock`, `rake`, `rubocop`,
`rubocop-rails-omakase`, `brakeman`, and `bundler-audit`.

Related: [[architecture]], [[commands]], [[api]], [[data-model]], [[gaps]].
