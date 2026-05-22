---
title: Dependencies
type: dependencies
source: git ls-files; Gemfile; xbookmark.gemspec; README.md
created: 2026-05-14
updated: 2026-05-22
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

The implementation worktree shells out to external tools:

- `codex` for LLM enrichment via `codex exec --json`.
- `qmd` for search collection registration, indexing, and querying.
- A whisper backend, detected from `WHISPER_BIN` or PATH candidates `whisper-cli`, `whisper-cpp`, `whisper`, and `faster-whisper`.
- System scheduler tools: `systemctl --user` on Linux and `launchctl` on macOS.

## External Services

- X API v2 for bookmarks and tweet details.
- Local OAuth callback server on loopback for PKCE login.
- Optional HTTP fetching of public external article links found in bookmarks, guarded by URL/IP safety checks.

## Contributor Checks

xbookmark mirrors Hive's baseline CI shape:

- `bundle exec rspec`
- `bundle exec rubocop --parallel --format github`
- `bundle exec brakeman --force --no-pager --quiet --format github --ignore-config config/brakeman.ignore`
- `bundle exec bundler-audit check --update`

The development/test bundle includes `rspec`, `webmock`, `rake`, `rubocop`,
`rubocop-rails-omakase`, `brakeman`, and `bundler-audit`.

Related: [[architecture]], [[commands]], [[api]], [[data-model]], [[gaps]].
