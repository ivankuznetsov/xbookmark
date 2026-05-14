---
title: Architecture
type: architecture
source: git ls-files; git worktree list; .hive-state/config.yml; ../xbookmark.worktrees/i-want-to-create-a-260504-1253/lib/xbookmark/**/*.rb; ../xbookmark.worktrees/create-proper-readme-md-for-260513-2ba1/README.md
created: 2026-05-14
updated: 2026-05-14
tags: [architecture]
---

**TLDR**: `xbookmark` has a minimal `main` branch today, plus Hive-managed worktrees containing an unmerged Ruby CLI implementation and a separate README/spec branch.

## Repository Shape

- `main` currently tracks only `.gitignore` and `LICENSE`; the working tree also has untracked LLM wiki and agent context files.
- `.hive-state/config.yml` identifies the project as `xbookmark`, default branch `main`, worktree root `/home/asterio/Dev/xbookmark.worktrees`, and Hive review settings.
- The completed worktree branch `i-want-to-create-a-260504-1253` contains the Ruby CLI implementation.
- The active review worktree branch `create-proper-readme-md-for-260513-2ba1` contains README and demo asset work only.

Branch-scoped claims below are intentionally labeled; do not assume they have landed on `main`.

## Implemented CLI Worktree

The implementation branch is a Ruby command-line application named `xbookmark`. Its runtime shape is:

- Entry point: `bin/xbookmark` dispatches to `Xbookmark::CLI` in `lib/xbookmark/cli.rb`.
- Configuration: `Xbookmark::Config` reads `.env` sources and XDG/macOS defaults, with required `X_CLIENT_ID` and `X_USER_ID`.
- X API integration: `Xbookmark::X::Auth` handles OAuth 2.0 PKCE and token refresh; `Xbookmark::X::Client` reads X bookmarks and tweet details from X API v2.
- State: `Xbookmark::State::Store` keeps local SQLite state under `<vault>/.xbookmark/state.db`.
- Sync loop: `Xbookmark::Sync::Runner` drives backfill, sync, and resync modes; `Xbookmark::Sync::Pipeline` processes one bookmark at a time.
- Media and transcription: `Xbookmark::Media::Downloader` downloads X media, and `Xbookmark::Transcribe::Whisper` shells out to a local whisper backend.
- Enrichment: `Xbookmark::Enrich::Orchestrator` calls `Xbookmark::Enrich::Codex`, fetches allowed external links, runs image OCR/captioning, and returns structured enrichment data.
- Rendering: `Xbookmark::Render::BookmarkRenderer` writes per-bookmark markdown; `Xbookmark::Render::AuxPage` maintains author, topic, entity, and thread pages.
- Search: `Xbookmark::Qmd::Registrar` registers/indexes the `bookmarks` QMD collection; `Xbookmark::Qmd::Searcher` shells out to `qmd query`.
- Scheduling: `Xbookmark::Scheduler::Systemd` installs a user timer on Linux; `Xbookmark::Scheduler::Launchd` installs a launch agent on macOS.

Related details: [[commands]], [[data-model]], [[dependencies]].

## Runtime Flow

```text
X API bookmarks
  -> local media download
  -> optional whisper transcription
  -> codex enrichment
  -> markdown + media in the vault
  -> QMD indexing for search
```

Per-bookmark work uses a scratch directory and atomic writes before updating state, so a failed bookmark should be retried rather than leaving partial final output.

## README Review Worktree

The README branch describes a more polished public-facing spec with install sections, configuration, command examples, scheduling docs, and a demo GIF. It is not tracked on `main` yet and has its own review/fix history in Hive stage `5-review`.

## Cross-Project Wiki Context

Configured main wiki path `/home/asterio/wikis/master/wiki` exists. A search for `xbookmark`, bookmark, Hive, and related terms found no xbookmark-specific page; only portfolio-wide Rails conventions and patterns were relevant. Because this repository is a Ruby CLI rather than a Rails app, those Rails conventions are background context, not architecture evidence for this project.

## Maintenance

Managed LLM wiki context lives in `.llm-wiki/config.json`, `AGENTS.md`, `CLAUDE.md`, and `wiki/`.

Related: [[dependencies]], [[active-areas]], [[commands]], [[data-model]], [[gaps]].
