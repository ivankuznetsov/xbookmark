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
