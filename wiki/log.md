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
**Decision:** CI runs the coverage Rake task, RuboCop with the 37signals omakase base, Brakeman, and bundler-audit. The local RuboCop config keeps xbookmark's existing array-bracket style to avoid a broad mechanical rewrite.
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

## [2026-05-22T20:40:00Z] find limit enforcement

**Action:** Added an xbookmark-side cap to QMD search results after production `bin/xbookmark find ... --limit 3` returned four hits from the installed QMD.
**Pages updated:** wiki/commands.md, wiki/log.md
**Source:** Live production `bin/xbookmark find Transcript --limit 3`, `lib/xbookmark/qmd/searcher.rb`, `spec/xbookmark/qmd/searcher_spec.rb`.

## [2026-05-22T21:05:00Z] production learning capture

**Action:** Consolidated the most important live production setup/backfill lessons into a dedicated wiki page and added the user-facing X pagination/idempotency notes to the README.
**Pages created:** wiki/live-production-learnings.md
**Pages updated:** README.md, wiki/index.md, wiki/decisions.md, wiki/gaps.md, wiki/active-areas.md, wiki/log.md
**Source:** Production install/backfill/transcription/search/scheduler verification, X API pagination probes, bookmark folder probe, duplicate audit, PRs #10-#12.

## [2026-05-22T22:05:00Z] bookmark page-size correction

**Action:** Corrected the X bookmark pagination finding: production `max_results=100` returned 98 IDs and no token, but `max_results=50` returned 4,745 unique IDs over 95 pages. xbookmark should use 50-item bookmark pages.
**Pages updated:** README.md, wiki/api.md, wiki/active-areas.md, wiki/commands.md, wiki/decisions.md, wiki/gaps.md, wiki/live-production-learnings.md, wiki/log.md
**Source:** Read-only production X API probes from `/home/asterio/Dev/xbookmark.install/xbookmark`.

## [2026-05-22T22:35:00Z] 100-percent coverage gate

**Action:** Added real behavioral tests across CLI dispatch, config/path discovery, OAuth, X API retries/errors, QMD, scheduler install/uninstall/status, media/transcription, rendering, sync pipeline/runner, and the executable wrapper. Added `bundle exec rake coverage` using Ruby's built-in `Coverage` API to enforce 100% line coverage over `bin/` and `lib/`.
**Pages updated:** wiki/dependencies.md, wiki/log.md
**Bug fixed:** `LinkFetcher#resolve` now fails closed when DNS resolution raises after a hostname parse miss.
**Verification:** After merging into current `main`, `bundle exec rake coverage` passed with 299 examples at 100.00% (2297/2297), and `bundle exec rubocop` passed with no offenses.
**Source:** `Rakefile`, `bin/xbookmark`, `lib/xbookmark/enrich/link_fetcher.rb`, and expanded specs under `spec/`.

## [2026-05-25T10:55:00Z] codex service tier setup fix

**Action:** Added setup/install cleanup for stale invalid top-level Codex `service_tier` values after production wiki maintenance failed on `service_tier = "default"` and docs review showed setup should not force Codex speed modes.
**Pages updated:** README.md, wiki/decisions.md, wiki/log.md
**Source:** `lib/xbookmark/codex_config.rb`, `lib/xbookmark/cli/setup.rb`, `lib/xbookmark/cli/install.rb`, `test/xbookmark/codex_config_test.rb`, `test/xbookmark/cli/setup_test.rb`, `test/xbookmark/cli_test.rb`, `README.md`.

## [2026-05-25T10:56:00Z] llm-wiki refresh

**Action:** Refreshed project wiki pages from current config, recent log entries, cross-project wiki search, recent git history, coverage work, and Codex service-tier setup changes.
**Pages updated:** wiki/architecture.md, wiki/api.md, wiki/commands.md, wiki/data-model.md, wiki/dependencies.md, wiki/active-areas.md, wiki/decisions.md, wiki/live-production-learnings.md, wiki/gaps.md, wiki/index.md, wiki/log.md
**Main wiki:** searched `/home/asterio/wikis/master/wiki`; no xbookmark-specific page found. `~/wikis/main/wiki`, `../wikis/master/wiki`, and `../wikis/main/wiki` did not exist.
**QMD:** review follow-up ran bounded `qmd search` queries for Codex service-tier and large-prompt terms; no indexed hits were returned. This refresh intentionally avoided `qmd update` and `qmd embed` because the wrapper script owns bounded qmd maintenance.
**Source:** `.llm-wiki/config.json`, `AGENTS.md`, `CLAUDE.md`, `wiki/index.md`, `wiki/gaps.md`, recent `wiki/log.md`, `git log --name-status`, `git status --short`, `Rakefile`, `lib/xbookmark/codex_config.rb`, `lib/xbookmark/cli/setup.rb`, `lib/xbookmark/cli/install.rb`, `lib/xbookmark/enrich/link_fetcher.rb`, and related specs.

## [2026-05-25T11:40:00Z] codex large prompt fix

**Action:** Changed Codex enrichment invocation to pass prompts over stdin instead of argv after production backfill hit `Errno::E2BIG: Argument list too long - codex` on a large bookmark prompt.
**Pages updated:** wiki/decisions.md, wiki/live-production-learnings.md, wiki/log.md
**Source:** Live production backfill log, `lib/xbookmark/enrich/codex.rb`, `test/xbookmark/enrich/codex_test.rb`, `test/xbookmark/enrich/orchestrator_test.rb`, `test/integration/v1_acceptance_test.rb`.

## [2026-05-25T00:00:00Z] minitest fixture migration

**Action:** Migrated the RSpec suite to Minitest, replaced RSpec mocks with Mocha, moved tests from `spec/` to `test/`, and added JSON fixtures for X bookmark API pages.
**Pages updated:** README.md, wiki/dependencies.md, wiki/gaps.md, wiki/log.md
**Decision:** Contributor and CI test commands now use `bundle exec rake test`, while `bundle exec rake coverage` remains the enforced 100% line coverage gate for `bin/` and `lib/`.
**Verification:** `bundle exec rake coverage` passed with 301 runs, 1053 assertions, and 100.00% coverage (2297/2297).
**Source:** `Gemfile`, `Rakefile`, `.github/workflows/ci.yml`, `test/`, and `test/fixtures/x/`.

## [2026-05-30T13:59:52Z] dependency coverage refresh

**Action:** Refreshed dependency and related wiki coverage after commit `57ced9b` added AuthConfig TOML routing.
**Pages updated:** wiki/dependencies.md, wiki/architecture.md, wiki/data-model.md, wiki/commands.md, wiki/api.md, wiki/active-areas.md, wiki/decisions.md, wiki/gaps.md, wiki/index.md, wiki/log.md
**Dependency change:** `tomlrb (~> 2.0)` is now a runtime dependency, locked as `tomlrb 2.0.4`, for `~/.config/xbookmark/auth.toml` parsing.
**Uncertainty recorded:** AuthConfig storage exists and is tested directly, but no public AuthConfig routing CLI or README contract was found in this refresh.
**QMD:** `qmd search` was read-only and returned no results for the new auth-routing dependency terms; did not run `qmd update` or `qmd embed` because the post-commit wrapper owns bounded qmd maintenance.
**Source:** `AGENTS.md`, `.llm-wiki/config.json`, wiki index/dependencies/gaps/recent log, committed diff `57ced9b`, `Gemfile`, `Gemfile.lock`, `xbookmark.gemspec`, `Rakefile`, `README.md`, `lib/xbookmark/keystore/*.rb`, `lib/xbookmark/x/auth.rb`, `lib/xbookmark/cli/auth.rb`, and `test/xbookmark/keystore/*_test.rb`.

## [2026-05-30T14:10:56Z] auth routing wiki correction

**Action:** Corrected the wiki refresh after the HEAD wiki commit missed later provider auth-routing CLI and README changes on the branch.
**Pages updated:** wiki/api.md, wiki/commands.md, wiki/active-areas.md, wiki/architecture.md, wiki/data-model.md, wiki/dependencies.md, wiki/decisions.md, wiki/gaps.md, wiki/index.md, wiki/log.md
**Correction:** Public provider credential commands now exist: `auth login PROVIDER`, `auth bind PROVIDER OP_REF`, `auth list`, `auth show PROVIDER`, and `auth rm PROVIDER`.
**Uncertainty recorded:** Real host credential stores were not exercised in this refresh; tests cover the command and resolver plumbing with shims/mocks.
**Main wiki:** searched `/home/asterio/wikis/master/wiki` for xbookmark/auth-routing terms; no relevant page was found. `~/wikis/main/wiki`, `../wikis/master/wiki`, and `../wikis/main/wiki` did not exist.
**QMD:** Ran read-only `qmd search "xbookmark auth.toml AuthConfig tomlrb"` and got no results. Did not run `qmd update` or `qmd embed`; the post-commit wrapper owns bounded qmd maintenance.
**Source:** `AGENTS.md`, `.llm-wiki/config.json`, required wiki pages and recent log, HEAD wiki diff `7323a6d`, recent auth commits `57ced9b..40064cd`, `README.md`, `lib/xbookmark/cli.rb`, `lib/xbookmark/cli/auth.rb`, `lib/xbookmark/keystore/auth_config.rb`, `lib/xbookmark/keystore/resolver.rb`, `lib/xbookmark/keystore/provider.rb`, `xbookmark.gemspec`, and auth-related tests.

## [2026-05-30T14:30:50Z] post-review wiki refresh

**Action:** Rechecked the latest committed wiki-only diff `3fa1c95` against the provider auth source surface and narrowed stale maintenance provenance.
**Pages updated:** wiki/active-areas.md, wiki/gaps.md, wiki/log.md
**Coverage result:** No new page coverage was needed; existing auth-routing pages already matched `README.md`, `lib/xbookmark/cli/auth.rb`, `Xbookmark::Keystore::AuthConfig`, `Xbookmark::Keystore::Resolver`, and auth tests.
**Uncertainty recorded:** The local worktree/index could not provide full `git status` or cached-diff evidence because it references missing blob `26d9b9b4b284d58add70f2ed2d581a1ab503fa67`; direct source reads and `git show` were used instead.
**Main wiki:** searched `/home/asterio/wikis/master/wiki`; no xbookmark/auth-routing-specific page was found.
**QMD:** Did not run `qmd update` or `qmd embed`; the post-commit wrapper owns bounded qmd maintenance.
**Source:** `AGENTS.md`, `.llm-wiki/config.json`, `wiki/index.md`, `wiki/decisions.md`, `wiki/gaps.md`, recent `wiki/log.md`, latest committed diff `3fa1c95`, `README.md`, `lib/xbookmark/cli/auth.rb`, `lib/xbookmark/keystore/auth_config.rb`, `lib/xbookmark/keystore/resolver.rb`, `test/xbookmark/cli/auth_test.rb`, `test/integration/auth_e2e_test.rb`, `git log`, `git show`, `git ls-files -s`, and `git fsck`.

## [2026-06-06T03:25:36Z] keystore backend hardening refresh

**Action:** Refreshed wiki coverage after commit `3c01175` hardened provider keychain routing, libsecret/keychain not-found handling, and backend failure surfacing.
**Pages updated:** wiki/architecture.md, wiki/api.md, wiki/commands.md, wiki/dependencies.md, wiki/active-areas.md, wiki/decisions.md, wiki/gaps.md, wiki/index.md, wiki/log.md
**Coverage result:** No new page coverage was needed. Existing auth-routing and dependency pages now record that routed Linux platform-keychain lookups require both `secret-tool` and a non-empty `DBUS_SESSION_BUS_ADDRESS`, signal-killed keychain/libsecret reads raise hard errors, and libsecret deletes tolerate already-missing items so stale `auth.toml` routing can be cleared.
**Uncertainty recorded:** Real `secret-tool` and macOS `security` not-found exit codes remain unverified; the current heuristics are code- and test-backed but not live-backend verified.
**Main wiki:** searched `/home/asterio/wikis/master/wiki`; no xbookmark/auth-routing/libsecret-specific page was found.
**QMD:** Ran read-only `qmd search "xbookmark keystore libsecret keychain resolver DBUS not-found exitstatus"` and got no results. Did not run `qmd update` or `qmd embed`; the post-commit wrapper owns bounded qmd maintenance.
**Source:** `AGENTS.md`, `.llm-wiki/config.json`, `wiki/index.md`, `wiki/decisions.md`, `wiki/gaps.md`, recent `wiki/log.md`, committed diff `3c01175`, `lib/xbookmark/keystore/keychain.rb`, `lib/xbookmark/keystore/libsecret.rb`, `lib/xbookmark/keystore/resolver.rb`, `test/xbookmark/keystore/resolver_test.rb`, `test/xbookmark/keystore_test.rb`, `git show`, and direct source reads.

## [2026-06-06T03:27:48Z] auth resolver docs refresh

**Action:** Refreshed command and API surface coverage after commit `50a4d4f` aligned provider auth README/wiki docs with resolver behavior and moved provider-name validation to shared `Xbookmark::Keystore::Provider::NAME_PATTERN`.
**Pages updated:** wiki/architecture.md, wiki/api.md, wiki/commands.md, wiki/active-areas.md, wiki/decisions.md, wiki/log.md
**Coverage result:** No new page coverage was needed. Existing auth-routing pages now record that `CI=true` must be the exact string `true` unless `XBOOKMARK_KEYS_FROM_ENV=1` is set, CI/env-forced provider resolution bypasses `auth.toml` entirely, and `AuthConfig` validates hand-edited TOML provider sections through the same provider-name pattern used by CLI parsing.
**Uncertainty recorded:** No new uncertainty was introduced; the live backend verification and real credential-tool exit-code gaps remain in [[gaps]].
**Main wiki:** searched `/home/asterio/wikis/master/wiki`; no xbookmark/auth-routing-specific page was found.
**QMD:** Ran read-only `qmd search "xbookmark provider auth resolver system backend API commands README"`; it returned an unrelated Hive wiki hit and no xbookmark page. Did not run `qmd update` or `qmd embed`; the post-commit wrapper owns bounded qmd maintenance.
**Source:** `AGENTS.md`, `.llm-wiki/config.json`, `wiki/index.md`, `wiki/architecture.md`, `wiki/decisions.md`, `wiki/gaps.md`, recent `wiki/log.md`, committed diff `50a4d4f`, `README.md`, `lib/xbookmark/keystore/provider.rb`, `lib/xbookmark/keystore/auth_config.rb`, `lib/xbookmark/keystore/resolver.rb`, `test/integration/auth_e2e_test.rb`, `git show`, and direct source reads.
