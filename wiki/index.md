---
title: xbookmark Wiki
type: index
source: wiki/**/*.md
created: 2026-05-14
updated: 2026-05-25
tags: [index, wiki]
---

**TLDR**: Catalog of the LLM-maintained wiki for `xbookmark`.

Page count: 11
Updated: 2026-05-25

## Core Pages

- [[architecture]] - Runtime architecture, production-hardening state, Codex config cleanup, QMD registration, scheduling, and coverage gate.
- [[api]] - External API, OAuth callback, X API, QMD, Codex subprocess, and Codex config-file surfaces.
- [[commands]] - CLI command surface, fresh setup contract, first-run setup wizard, install, and uninstall behavior.
- [[data-model]] - SQLite state schema, bookmark wiki layout, statuses, modes, and transactional behavior.
- [[dependencies]] - Ruby gem dependencies, external CLIs, Codex/QMD/Whisper tools, scheduler tools, and contributor checks.
- [[decisions]] - Repository, workflow, runtime, setup, service-tier, and coverage decisions grounded in code/history.
- [[active-areas]] - Production hardening state, 50-item page-size landing, local coverage gate, and service-tier follow-up.
- [[live-production-learnings]] - Production backfill lessons, source limits, media/transcript fixes, Codex/QMD behavior, and reusable verification commands.

## Maintenance Pages

- [[gaps]] - Known uncertainty and verification gaps.
- [[index]] - This catalog.
- [[log]] - Append-only wiki changelog.

## Maintenance

- Managed config: `.llm-wiki/config.json`
- Headless refresh: `.llm-wiki/refresh-wiki.sh`
- Post-commit refresh: `.llm-wiki/post-commit-refresh.sh`
- Main cross-project wiki searched: `/home/asterio/wikis/master/wiki`
