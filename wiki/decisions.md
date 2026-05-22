---
title: Decisions
type: decisions
source: git log; git worktree list; .hive-state/config.yml; lib/xbookmark/**/*.rb; README.md; .env.example
created: 2026-05-14
updated: 2026-05-22
tags: [decisions]
---

**TLDR**: Current durable decisions center on an unreleased Ruby CLI that creates a standalone bookmark wiki from X data, separate from this repository's project LLM wiki.

## Repository and Workflow Decisions

- `main` is still a minimal baseline branch with `LICENSE` and `.gitignore`.
- `.hive-state/` is ignored by `.gitignore` and used as the local Hive workflow state store.
- Hive is configured with default branch `main`, worktree root `/home/asterio/Dev/xbookmark.worktrees`, `max_review_passes: 2`, and multiple reviewer agents.
- LLM wiki maintenance is managed through `.llm-wiki/` with `codex` as the headless maintenance agent.

## Runtime CLI Decisions

- Use Ruby with a Bundler/gemspec layout and a Thor CLI (`bin/xbookmark`, `lib/xbookmark/cli.rb`).
- Use official X API v2 with OAuth 2.0 PKCE and scopes visible in `Xbookmark::X::Auth`.
- Require `X_CLIENT_ID` and `X_USER_ID` at config load time; store access and refresh tokens back into the env file with file mode `0600`.
- Create a standalone bookmark wiki at `XBOOKMARK_WIKI_PATH`, separate from the project LLM wiki in `wiki/`.
- Default new installs to `xbookmark-wiki`; migration from the earlier local `xbookmark-vault` name is not needed because the product has not been released.
- Store local sync state in SQLite at `<bookmark-wiki>/.xbookmark/state.db`.
- Treat each bookmark as a transactional unit: scratch media/transcription/enrichment first, final markdown/media writes after success, then state update.
- Use Codex headless CLI for LLM enrichment instead of a direct provider SDK.
- Use local Whisper tooling for audio/video transcription.
- Register and query a QMD collection named `bookmarks`.
- Use systemd user timers on Linux and launchd on macOS for daily sync, and make scheduler installation part of the default setup flow.
- Fail closed for external link fetch safety by rejecting private, loopback, link-local, reserved, multicast, and metadata-address ranges.

## README Setup Decisions

- The README agent prompt must only reference commands that exist in the CLI so fresh installs work without manual correction.
- `bin/xbookmark install` is the scheduler command and default setup step; do not document `schedule install/status/uninstall` until those subcommands exist.
- `XBOOKMARK_ENV_FILE` is the alternate config-file selector; do not document `--config` or `XBOOKMARK_CONFIG` until implemented.
- `XBOOKMARK_WIKI_PATH` and `--wiki` are the preferred bookmark wiki path controls. `XBOOKMARK_VAULT`, `OBSIDIAN_VAULT_PATH`, and `--vault` remain compatibility aliases.
- `auth login` binds the callback host/port from `X_REDIRECT_URI`; there is no `auth login --port` option.

## Recent History Signals

- `main`: `99559b4 chore: ignore .hive-state worktree`.
- Implementation worktree: latest visible commits distinguish bookmark wiki configuration, ignore blank bookmark wiki path values, and reconcile README/wiki setup docs to the implemented CLI.

Related: [[architecture]], [[commands]], [[api]], [[data-model]], [[active-areas]], [[gaps]].
