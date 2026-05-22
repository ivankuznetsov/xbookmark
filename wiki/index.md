---
title: xbookmark Wiki
type: index
source: wiki/**/*.md
created: 2026-05-14
updated: 2026-05-22
tags: [index, wiki]
---

**TLDR**: Catalog of the LLM-maintained wiki for `xbookmark`.

Page count: 11
Updated: 2026-05-22

## Core Pages

- [[architecture]] - Branch-aware project architecture: runtime on `main` and current scheduler/QMD registration work.
- [[api]] - External API, OAuth callback, X API, and QMD registration/search surfaces with README/implementation mismatches.
- [[commands]] - CLI command surface and fresh setup contract.
- [[data-model]] - SQLite state schema, bookmark wiki layout, statuses, modes, and transactional behavior.
- [[dependencies]] - Ruby gem dependencies, external CLIs, X API, and local scheduler dependencies.
- [[decisions]] - Repository, workflow, runtime, and setup decisions grounded in code/history.
- [[active-areas]] - Current scheduler setup and QMD registration work on top of `main`.
- [[live-production-learnings]] - Production backfill lessons, source limits, media/transcript fixes, QMD behavior, and reusable verification commands.

## Maintenance Pages

- [[gaps]] - Known uncertainty and verification gaps.
- [[index]] - This catalog.
- [[log]] - Append-only wiki changelog.

## Maintenance

- Managed config: `.llm-wiki/config.json`
- Headless refresh: `.llm-wiki/refresh-wiki.sh`
- Post-commit refresh: `.llm-wiki/post-commit-refresh.sh`
- Main cross-project wiki searched: `/home/asterio/wikis/master/wiki`
