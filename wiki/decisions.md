---
title: Decisions
type: decisions
source: git log; git worktree list; .hive-state/config.yml; ../xbookmark.worktrees/i-want-to-create-a-260504-1253/lib/xbookmark/**/*.rb; ../xbookmark.worktrees/create-proper-readme-md-for-260513-2ba1/README.md; ../xbookmark.worktrees/create-proper-readme-md-for-260513-2ba1/.env.example
created: 2026-05-14
updated: 2026-05-14
tags: [decisions]
---

**TLDR**: Current durable decisions are split between `main` repository setup, Hive workflow state, unmerged implementation choices, and README branch contracts that still need reconciliation.

## Repository and Workflow Decisions

- `main` is still a minimal baseline branch with `LICENSE` and `.gitignore`.
- `.hive-state/` is ignored by `.gitignore` and used as the local Hive workflow state store.
- Hive is configured with default branch `main`, worktree root `/home/asterio/Dev/xbookmark.worktrees`, `max_review_passes: 2`, and multiple reviewer agents.
- LLM wiki maintenance is managed through `.llm-wiki/` with `codex` as the headless maintenance agent.

## Implementation Worktree Decisions

These are branch-scoped to `i-want-to-create-a-260504-1253` until merged:

- Use Ruby with a Bundler/gemspec layout and a Thor CLI (`bin/xbookmark`, `lib/xbookmark/cli.rb`).
- Use official X API v2 with OAuth 2.0 PKCE and scopes visible in `Xbookmark::X::Auth`.
- Require `X_CLIENT_ID` and `X_USER_ID` at config load time; store access and refresh tokens back into the env file with file mode `0600`.
- Store local sync state in SQLite at `<vault>/.xbookmark/state.db`.
- Treat each bookmark as a transactional unit: scratch media/transcription/enrichment first, final markdown/media writes after success, then state update.
- Use Codex headless CLI for LLM enrichment instead of a direct provider SDK.
- Use local Whisper tooling for audio/video transcription.
- Register and query a QMD collection named `bookmarks`.
- Use systemd user timers on Linux and launchd on macOS for daily sync.
- Fail closed for external link fetch safety by rejecting private, loopback, link-local, reserved, multicast, and metadata-address ranges.

## README Review Branch Decisions

Branch `create-proper-readme-md-for-260513-2ba1` is a README/spec branch in Hive review. It documents a public-facing install/config/usage story, includes `docs/assets/demo.gif`, and now restores managed wiki/agent context files.

Commit `8e6ad0e` intentionally ratified README-level contracts for:

- Explicit `auth refresh` and read-only `auth status`.
- Config discovery through `--config`, `XBOOKMARK_CONFIG`, repo `.env`, and user config `.env`.
- Backfill idempotency and `--overwrite`.
- QMD lexical/vector/HyDE find behavior and JSON output shape.
- `schedule` commands with scheduler selection and config path.
- Credential path and permission claims.
- Accepted Whisper model names.
- Contributor checks including `rubocop` and `brakeman`.

Several of these contracts are not present in the implementation branch source read during this refresh; see [[commands]], [[api]], and [[gaps]] before treating them as runtime decisions.

## Recent History Signals

- `main`: `99559b4 chore: ignore .hive-state worktree`.
- Implementation worktree: latest visible commits are fixes around bookmark date fallback/media embeds, sync timestamps/QMD registration, and README clarification.
- README worktree: latest visible commits apply review triage fixes to `.env.example`, `.gitignore`, `README.md`, the demo asset, and restored managed wiki/agent context. `8e6ad0e` is the latest commit read for this refresh.

Related: [[architecture]], [[commands]], [[api]], [[data-model]], [[active-areas]], [[gaps]].
