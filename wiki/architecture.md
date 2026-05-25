---
title: Architecture
type: architecture
source: git ls-files; lib/xbookmark/**/*.rb; README.md; .env.example; .llm-wiki/*
created: 2026-05-14
updated: 2026-05-25
tags: [architecture]
---

**TLDR**: `xbookmark` is a Ruby CLI that ingests X bookmarks into a standalone local bookmark wiki, enriches them locally, and indexes them with QMD.

## Repository Shape

- `main` tracks the runtime CLI, README, env template, CI config, specs, and project wiki.
- Production-hardening work includes 50-item X bookmark pagination, Codex stdin prompt delivery, stale service-tier cleanup, and the 100% coverage gate.
- `.hive-state/config.yml` identifies the project as `xbookmark`, default branch `main`, worktree root `/home/asterio/Dev/xbookmark.worktrees`, and Hive review settings.

## Runtime CLI

The application is a Ruby command-line application named `xbookmark`. Its runtime shape is:

- Entry point: `bin/xbookmark` dispatches to `Xbookmark::CLI` in `lib/xbookmark/cli.rb`.
- Configuration: `Xbookmark::Config` reads `.env` sources and XDG/macOS defaults, with required `X_CLIENT_ID` and `X_USER_ID`.
- X API integration: `Xbookmark::X::Auth` handles OAuth 2.0 PKCE and token refresh; `Xbookmark::X::Client` reads X bookmarks and tweet details from X API v2.
- State: `Xbookmark::State::Store` keeps local SQLite state under `<bookmark-wiki>/.xbookmark/state.db`.
- Sync loop: `Xbookmark::Sync::Runner` drives backfill, sync, and resync modes; `Xbookmark::Sync::Pipeline` processes one bookmark at a time.
- Media and transcription: `Xbookmark::Media::Downloader` downloads full-size X media without a default byte cap, and `Xbookmark::Transcribe::Whisper` extracts video audio through `ffmpeg` before shelling out to a local whisper backend with duration-aware timeouts.
- Enrichment: `Xbookmark::Enrich::Orchestrator` calls `Xbookmark::Enrich::Codex`, fetches allowed external links, runs image OCR/captioning, and returns structured enrichment data.
- Rendering: `Xbookmark::Render::BookmarkRenderer` writes per-bookmark markdown; `Xbookmark::Render::AuxPage` maintains author, topic, entity, and thread pages. Aux landing pages are created during normal sync, but their separate LLM summaries are opt-in through `XBOOKMARK_AUX_SUMMARIES` so large backfills stay focused on bookmark notes.
- Search: `Xbookmark::Qmd::Registrar` registers the `bookmarks` QMD collection through current `qmd collection` commands with legacy fallbacks; `Xbookmark::Qmd::Searcher` shells out to `qmd query`.
- Scheduling: `Xbookmark::Scheduler::Systemd` installs a user timer on Linux and tries to enable user linger; `Xbookmark::Scheduler::Launchd` installs a launch agent on macOS.
- Setup safety: `Xbookmark::CodexConfig` removes only stale invalid top-level `service_tier` values in `~/.codex/config.toml` or `$CODEX_HOME/config.toml`, preserves valid speed modes and project tables, and rewrites changed config files atomically with `0600` permissions.
- Coverage: `bundle exec rake coverage` uses Ruby's built-in `Coverage` API while running RSpec, then aborts unless every counted line under `bin/` and `lib/` is covered.

Related details: [[commands]], [[data-model]], [[dependencies]].

## Runtime Flow

```text
X API bookmarks
  -> local media download
  -> optional whisper transcription
  -> codex enrichment
  -> markdown + media in the bookmark wiki
  -> QMD indexing for search
```

Per-bookmark work uses a scratch directory and atomic writes before updating state, so a failed bookmark should be retried rather than leaving partial final output.

## Cross-Project Wiki Context

Configured main wiki path `/home/asterio/wikis/master/wiki` exists. A search for `xbookmark`, bookmark, Hive, and related terms found no xbookmark-specific page; only portfolio-wide Rails conventions and patterns were relevant. Because this repository is a Ruby CLI rather than a Rails app, those Rails conventions are background context, not architecture evidence for this project.

## Maintenance

Managed LLM wiki context lives in `.llm-wiki/config.json`, `AGENTS.md`, `CLAUDE.md`, and `wiki/`.

Related: [[dependencies]], [[active-areas]], [[commands]], [[api]], [[data-model]], [[gaps]].
