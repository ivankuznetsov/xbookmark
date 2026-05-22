---
title: Active Areas
type: active-areas
source: git log --name-only; git status; README.md; lib/xbookmark/config.rb; lib/xbookmark/cli.rb
created: 2026-05-14
updated: 2026-05-22
tags: [activity]
---

**TLDR**: Production backfill reliability work has landed on `main`; the current follow-up is switching bookmark ingestion to 50-item pages because X returned thousands of older bookmarks only at that page size.

## Active Branch

`main` includes the production setup/backfill fixes from PRs 10-12:

- README setup now runs `bin/xbookmark install` as a required daily scheduler step instead of asking whether to install it.
- Linux scheduler setup tries to enable systemd linger through `loginctl enable-linger <user>` so the daily timer can fire after logout.
- Media downloads no longer impose the old 200 MB default cap; full-size X media is downloaded.
- Bookmark ingestion should request 50 items per X API page. Live production returned 4,745 unique bookmarks with `max_results=50`, but only 98 and no `next_token` with `max_results=100`.
- `WHISPER_MODEL=base.en` resolves to a local whisper.cpp `ggml-base.en.bin` model file when using `whisper-cli`/`whisper-cpp`; setup docs now include the model download step.
- Whisper transcription extracts downloaded video audio with `ffmpeg`, treats no-audio MP4s as empty transcripts, uses duration-aware timeouts, and runs whisper.cpp with up to 8 CPU threads by default.
- Large backfills now skip separate aux-page LLM summaries by default; author/topic/entity/thread pages are still written for Obsidian graph/backlinks, and `XBOOKMARK_AUX_SUMMARIES=true` restores the extra summaries.
- `Xbookmark::Qmd::Registrar` tries current `qmd collection list`/`collection add` first and preserves legacy command fallbacks.
- `Xbookmark::Enrich::Codex` unwraps current `codex exec --json` `item.completed` agent messages.
- Specs cover the README setup contract, legacy registrar fallback, scheduler linger setup, and current Codex JSON event parsing.
- The earlier `XBOOKMARK_WIKI_PATH` runtime wiki terminology is already on `main`.
- Production verification and reusable lessons are summarized in [[live-production-learnings]].

## Setup Reliability

The README now describes only implemented setup commands:

- `bin/xbookmark auth login`
- `bin/xbookmark auth status`
- `bin/xbookmark install`
- `bin/xbookmark backfill [--limit N]`
- `bin/xbookmark sync`
- `bin/xbookmark find QUERY [--limit N]`
- `bin/xbookmark install [--time HH:MM] [--dry-run] [--uninstall]`

Deferred command shapes such as `schedule`, `auth refresh/logout`, `enrich`, `--config`, `backfill --since`, and `find --json` should stay out of setup docs until implemented.

Related: [[architecture]], [[commands]], [[api]], [[dependencies]], [[gaps]].
