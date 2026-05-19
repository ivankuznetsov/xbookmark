---
title: Dependencies
type: dependencies
source: git ls-files; ../xbookmark.worktrees/i-want-to-create-a-260504-1253/Gemfile; ../xbookmark.worktrees/i-want-to-create-a-260504-1253/xbookmark.gemspec; ../xbookmark.worktrees/i-want-to-create-a-260504-1253/README.md; ../xbookmark.worktrees/create-proper-readme-md-for-260513-2ba1/README.md
created: 2026-05-14
updated: 2026-05-14
tags: [dependencies]
---

**TLDR**: `main` has no runtime dependency files; the implementation worktree is a Ruby gem-style CLI, while the README branch documents some dependency expectations that are not yet reflected in manifests.

## Main Branch

- No `Gemfile`, gemspec, package manifest, lockfile, or application source is tracked on `main`.
- The only tracked project files are `.gitignore` and `LICENSE`.

## Implementation Worktree: Ruby Dependencies

Branch `i-want-to-create-a-260504-1253` contains:

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

## README Branch Dependency Claims

The README review branch documents user-facing prerequisites and contributor checks without adding runtime manifests on that branch:

- Ruby 3.3 or newer, while the implementation gemspec currently says `>= 3.1`.
- Platform packages for Ruby, SQLite headers, `ffmpeg`, `git`, and Whisper tooling.
- `codex` CLI authenticated through `codex login`.
- QMD as the markdown search engine behind `find`.
- Contributor checks `bundle exec rake test`, `bundle exec rubocop`, and `bundle exec brakeman`; the implementation Gemfile read during this refresh includes `rspec`, `webmock`, and `rake`, but not `rubocop` or `brakeman`.

These are documentation contracts until the implementation branch manifests are reconciled.

Related: [[architecture]], [[commands]], [[api]], [[data-model]], [[gaps]].
