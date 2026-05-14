---
title: xbookmark Wiki
type: index
source: wiki/**/*.md
created: 2026-05-14
updated: 2026-05-14
tags: [index, wiki]
---

**TLDR**: Catalog of the LLM-maintained wiki for `xbookmark`.

Page count: 9
Updated: 2026-05-14

## Core Pages

- [[architecture]] - Branch-aware project architecture: minimal `main`, implementation worktree, README review worktree.
- [[commands]] - CLI command surface from the implementation worktree plus README mismatch notes.
- [[data-model]] - SQLite state schema, vault layout, statuses, modes, and transactional behavior.
- [[dependencies]] - Ruby gem dependencies, external CLIs, X API, and local scheduler dependencies.
- [[decisions]] - Repository, workflow, implementation, and README branch decisions grounded in code/history.
- [[active-areas]] - Recent activity across `main`, implementation worktree, README review worktree, and Hive state.

## Maintenance Pages

- [[gaps]] - Known uncertainty, branch reconciliation needs, and verification gaps.
- [[index]] - This catalog.
- [[log]] - Append-only wiki changelog.

## Maintenance

- Managed config: `.llm-wiki/config.json`
- Headless refresh: `.llm-wiki/refresh-wiki.sh`
- Post-commit refresh: `.llm-wiki/post-commit-refresh.sh`
- Main cross-project wiki searched: `/home/asterio/wikis/master/wiki`
