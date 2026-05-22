# Wiki Changelog

Append-only log of meaningful wiki updates.

## [2026-05-14T16:53:27Z] bootstrap

**Action:** Managed llm-wiki bootstrap from codebase and Hive registry.
**Pages created:** wiki/active-areas.md, wiki/architecture.md, wiki/decisions.md, wiki/dependencies.md, wiki/gaps.md, wiki/index.md, wiki/log.md
**Pages updated:** wiki/index.md, wiki/log.md, wiki/gaps.md, .llm-wiki/config.json, AGENTS.md, CLAUDE.md, .claude/settings.json
**QMD:** qmd missing
**Scheduler:** files written; systemctl enable failed for llm-wiki-xbookmark-e08e1f34.timer
**Post-commit hook:** /home/asterio/Dev/xbookmark/.git/hooks/post-commit
**Source:** Codebase read + git history

## [2026-05-14T17:07:29Z] refresh

**Action:** Refreshed wiki after reading `.llm-wiki/config.json`, `AGENTS.md`, existing wiki pages, recent log entries, configured main wiki path, default main wiki paths, git history, Hive state, and worktree source files.
**Pages created:** wiki/commands.md, wiki/data-model.md
**Pages updated:** wiki/architecture.md, wiki/dependencies.md, wiki/decisions.md, wiki/active-areas.md, wiki/gaps.md, wiki/index.md, wiki/log.md
**Main wiki:** searched `/home/asterio/wikis/master/wiki`; no xbookmark-specific page found. Other requested default main wiki paths did not exist.
**QMD:** qmd available; `qmd search` used during refresh.
**Source:** `main` git history, `.hive-state/config.yml`, Hive stage files, `git worktree list`, implementation worktree `i-want-to-create-a-260504-1253`, README review worktree `create-proper-readme-md-for-260513-2ba1`

## [2026-05-14T17:26:52Z] llm-wiki validation

**Action:** Validated managed llm-wiki bootstrap and scheduled maintenance after Hive registry bootstrap.
**Headless agent:** Codex (`.llm-wiki/config.json` has `headless_agent: "codex"`).
**Context:** `AGENTS.md` and `CLAUDE.md` contain the managed LLM WIKI block; Claude `SessionStart` prints `wiki/index.md` and recent `wiki/log.md`.
**QMD:** `qmd 2.1.0` collection update, embed, and `qmd search` succeeded for this collection after the scheduled refresh test. QMD attempted GPU first and fell back to CPU because Vulkan headers are missing.
**Scheduler:** `llm-wiki-xbookmark-e08e1f34.timer` is enabled and active under `systemctl --user`; next run is scheduled for 2026-05-15 18:03:41 BST.
**Maintenance scripts:** `.llm-wiki/refresh-wiki.sh` and `.llm-wiki/post-commit-refresh.sh` use bounded Codex and qmd timeouts and tell headless Codex not to run `qmd update` or `qmd embed` itself.
**Source:** `systemctl --user list-timers`, `qmd update`, `qmd embed`, and collection-scoped `qmd search`.

## [2026-05-14T19:37:29Z] README review fix

**Action:** Restored wiki context into the README review worktree and updated the command mismatch note after the README changed `auth status` to read-only with an explicit `auth refresh`.
**Pages updated:** wiki/commands.md, wiki/log.md
**Source:** README review worktree fix pass 04.

## [2026-05-14T19:43:18Z] command-api refresh

**Action:** Refreshed command and API surface coverage after commit `8e6ad0e` expanded README contracts for auth, config discovery, backfill idempotency, QMD find behavior, scheduling, credential paths, Whisper models, and contributor checks.
**Pages created:** wiki/api.md
**Pages updated:** wiki/commands.md, wiki/architecture.md, wiki/decisions.md, wiki/dependencies.md, wiki/active-areas.md, wiki/gaps.md, wiki/index.md, wiki/log.md
**Main wiki:** searched `/home/asterio/wikis/master/wiki`; no xbookmark-specific page found. Read relevant OAuth, command execution, and SSRF notes from master wiki context.
**QMD:** not run; the post-commit wrapper owns bounded qmd maintenance for this refresh.
**Source:** latest committed diff `8e6ad0e`, README branch `README.md`, `.env.example`, `.gitignore`, Hive review task file, implementation branch `bin/xbookmark`, `lib/xbookmark/cli*.rb`, `lib/xbookmark/config.rb`, `lib/xbookmark/x/auth.rb`, `lib/xbookmark/x/client.rb`, `lib/xbookmark/qmd/searcher.rb`, scheduler files, and gem manifests.

## [2026-05-22T13:18:15Z] setup-contract refresh

**Action:** Updated the project wiki after PR review clarified that xbookmark is unreleased and new setups should follow the implemented CLI only.
**Pages updated:** wiki/commands.md, wiki/gaps.md, wiki/decisions.md, wiki/data-model.md, wiki/index.md, wiki/api.md, wiki/architecture.md, wiki/dependencies.md, wiki/active-areas.md, wiki/log.md
**Decision:** Runtime output is a standalone bookmark wiki configured by `XBOOKMARK_WIKI_PATH`; this repository's `wiki/` remains the project LLM wiki. The `xbookmark-wiki` default does not need migration from `xbookmark-vault` before release.
**Source:** `README.md`, `.env.example`, `lib/xbookmark/config.rb`, `lib/xbookmark/cli.rb`, `lib/xbookmark/cli/*.rb`, scheduler implementation, and review findings for PR #7.

## [2026-05-22T13:36:38Z] ci-checks refresh

**Action:** Added Hive-style CI checks for xbookmark and updated contributor docs.
**Pages updated:** wiki/dependencies.md, wiki/log.md
**Decision:** CI runs RSpec, RuboCop with the 37signals omakase base, Brakeman, and bundler-audit. The local RuboCop config keeps xbookmark's existing array-bracket style to avoid a broad mechanical rewrite.
**Source:** Hive `.github/workflows/ci.yml`, Hive Dependabot/PR template, xbookmark Gemfile, `.rubocop.yml`, `.github/workflows/ci.yml`, and local check outputs.

## [2026-05-22T15:23:06Z] default scheduler setup refresh

**Action:** Made daily scheduler installation part of the default setup contract and aligned QMD registration with the installed `qmd collection add` CLI while preserving legacy command fallback.
**Pages updated:** wiki/commands.md, wiki/gaps.md, wiki/decisions.md, wiki/active-areas.md, wiki/log.md
**Source:** `README.md`, `lib/xbookmark/qmd/registrar.rb`, `spec/xbookmark/qmd/registrar_spec.rb`, production install output.
