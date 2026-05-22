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

## [2026-05-22T15:28:29Z] command-api coverage refresh

**Action:** Refreshed command/API coverage after commit `8c5833f` touched README setup flow and QMD registrar behavior; also corrected stale branch/main wiki context.
**Pages updated:** wiki/api.md, wiki/commands.md, wiki/architecture.md, wiki/active-areas.md, wiki/decisions.md, wiki/data-model.md, wiki/dependencies.md, wiki/gaps.md, wiki/index.md, wiki/log.md
**Main wiki:** searched `/home/asterio/wikis/master/wiki`; no xbookmark/QMD/scheduler-specific page found. Other default main wiki paths did not exist.
**QMD:** `qmd search` was read-only and returned stale indexed snippets; did not run `qmd update` or `qmd embed` because the post-commit wrapper owns bounded qmd maintenance.
**Gap recorded:** `.env.example` still references `--port`, but the implemented auth command uses `X_REDIRECT_URI` and has no `auth login --port` flag.
**Source:** `AGENTS.md`, `.llm-wiki/config.json`, wiki core pages and recent log entries, latest committed diff `8c5833f`, `README.md`, `.env.example`, `lib/xbookmark/cli.rb`, `lib/xbookmark/cli/auth.rb`, `lib/xbookmark/cli/install.rb`, `lib/xbookmark/x/auth.rb`, `lib/xbookmark/qmd/registrar.rb`, `lib/xbookmark/qmd/searcher.rb`, scheduler files, `spec/readme_contract_spec.rb`, `spec/xbookmark/qmd/registrar_spec.rb`, and `main..HEAD` diff.

## [2026-05-22T15:40:00Z] linger setup refresh

**Action:** Added Linux systemd linger enablement to scheduler install so default setup can run daily timers after logout, and fixed `.env.example` to avoid the nonexistent `--port` option.
**Pages updated:** wiki/commands.md, wiki/architecture.md, wiki/active-areas.md, wiki/decisions.md, wiki/dependencies.md, wiki/gaps.md, wiki/log.md
**Source:** `README.md`, `.env.example`, `lib/xbookmark/scheduler/systemd.rb`, `spec/xbookmark/scheduler/systemd_spec.rb`, `spec/readme_contract_spec.rb`.

## [2026-05-22T15:55:00Z] codex-jsonl live setup fix

**Action:** Updated Codex enrichment parsing after live production backfill showed current `codex exec --json` emits final JSON under `item.completed` agent-message events.
**Pages updated:** wiki/api.md, wiki/active-areas.md, wiki/gaps.md, wiki/log.md
**Source:** Live `bin/xbookmark backfill --limit 100` failure, `lib/xbookmark/enrich/codex.rb`, `spec/xbookmark/enrich/codex_spec.rb`.

## [2026-05-22T16:10:00Z] large media download setup fix

**Action:** Removed the default 200 MB media download cap after live production backfill hit `Down::TooLarge` on X video variants.
**Pages updated:** wiki/architecture.md, wiki/active-areas.md, wiki/gaps.md, wiki/log.md
**Source:** Live `bin/xbookmark backfill --limit 100` failure, `lib/xbookmark/media/downloader.rb`, `spec/xbookmark/media/downloader_spec.rb`.

## [2026-05-22T17:35:00Z] whisper model setup fix

**Action:** Fixed whisper.cpp model resolution so `WHISPER_MODEL=base.en` resolves to a local `ggml-base.en.bin` file and documented the model download step in setup instructions.
**Pages updated:** wiki/active-areas.md, wiki/dependencies.md, wiki/log.md
**Production check:** Downloaded `ggml-base.en.bin` into the production whisper.cpp checkout and reran all Whisper-failed media rows; state ended with 31 bookmarks done and zero Whisper failures.
**Source:** Live production resync failures, `lib/xbookmark/transcribe/whisper.rb`, `spec/xbookmark/transcribe/whisper_spec.rb`, `README.md`.

## [2026-05-22T18:15:00Z] backfill speed path

**Action:** Removed the planning Codex call from bookmark enrichment, filtered out X media/status URLs from article fetching, and made separate aux-page LLM summaries opt-in.
**Pages updated:** wiki/architecture.md, wiki/data-model.md, wiki/active-areas.md, wiki/dependencies.md, wiki/log.md
**Decision:** Bookmark notes remain enriched and link to author/topic/entity/thread pages. Aux landing pages are still written for Obsidian graph/backlinks, but their own summaries are disabled by default so 100+ bookmark backfills do not spend most runtime on per-slug summaries.
**Source:** Live 31-bookmark production wiki had 302 aux pages and 300 aux summaries, far exceeding the bookmark-note work.

## [2026-05-22T19:55:00Z] whisper media rerun fix

**Action:** Fixed whisper.cpp transcription for downloaded X videos by extracting audio through `ffmpeg`, adding duration-aware timeouts for long media, using more CPU threads by default, and treating no-audio videos as empty transcripts instead of retry failures.
**Pages updated:** wiki/architecture.md, wiki/dependencies.md, wiki/active-areas.md, wiki/log.md
**Production check:** Reran Whisper over 20 production MP4 files. Eighteen produced non-empty transcript sidecars and were injected into bookmark markdown; two MP4s had no audio stream and cleanly produced empty transcript sidecars.
**Source:** Live production media rerun, `lib/xbookmark/transcribe/whisper.rb`, `lib/xbookmark/cli/doctor.rb`, `spec/xbookmark/transcribe/whisper_spec.rb`, `README.md`, `.env.example`.
