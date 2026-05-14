---
title: Active Areas
type: active-areas
source: git log --name-only; git worktree list; .hive-state/stages/**/task.md; ../xbookmark.worktrees/*/git log
created: 2026-05-14
updated: 2026-05-14
tags: [activity]
---

**TLDR**: `main` has almost no source activity, but Hive worktrees show active CLI implementation and README/spec review work.

## Main Branch

- `99559b4 chore: ignore .hive-state worktree`
- `e960fed Initial commit`

Tracked source on `main` remains limited to `.gitignore` and `LICENSE`.

## Completed Implementation Worktree

Branch `i-want-to-create-a-260504-1253` is marked complete in `.hive-state/stages/7-done/.../task.md` and contains the Ruby CLI implementation.

Recent visible commits on that branch include:

- `8f45a6d docs: clarify bookmarked_at semantics, drop Windows-only PATHEXT lookup`
- `6ce9f75 fix(sync): only stamp last_sync on real runs, ensure qmd registration in reindex`
- `ac74988 fix(render): stable bookmark date fallback, Obsidian-friendly media embeds`
- `f49328e fix(qmd): surface JSON parse errors, exact collection match, require fileutils`
- `d6c28ad fix(whisper): raise WhisperUnavailable for subprocess failure, bound runtime`
- `950cd09 fix(link-fetcher): block SSRF to private/loopback/metadata addresses`
- Earlier feature commits added scaffold/config, state, X API auth/client, media, transcription, enrichment, rendering, sync, CLI, QMD, scheduler, and acceptance tests.

`git diff main...HEAD` in that worktree reports 72 files and 5155 insertions, including `Gemfile`, `xbookmark.gemspec`, `bin/xbookmark`, `lib/xbookmark/**/*.rb`, and `spec/**/*.rb`.

## Active README Review Worktree

Branch `create-proper-readme-md-for-260513-2ba1` is in `.hive-state/stages/5-review/...` and `task.md` records `REVIEW_ERROR phase=fix reason=fix_failed pass=4`.

Recent visible commits on that branch include:

- `7d9fd00 docs(env): warn that .env.example must stay credential-free`
- `66dd62c docs(readme): apply triage fix pass 04`
- `b9a6482 fix(gitignore): ignore /.env to prevent X credential leaks`
- Prior commits build the README sections and add `docs/assets/demo.gif`.

`git diff main...HEAD` in that worktree reports README, `.env.example`, `.gitignore`, and demo asset changes only.

## Current Working Tree

The main checkout has untracked wiki/agent files and `.gitignore` modifications from LLM wiki bootstrap/refresh. These were preserved and updated in place.

Related: [[architecture]], [[commands]], [[dependencies]], [[gaps]].
