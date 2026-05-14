# Wiki Gaps

| Area | Gap | Notes |
|------|-----|-------|
| Main branch coverage | Runtime source is not on `main` | `main` tracks only `.gitignore` and `LICENSE`; architecture, commands, dependencies, and data-model pages document unmerged Hive worktrees and say so explicitly. |
| Branch reconciliation | README/spec branch and implementation branch may drift | README review branch mentions command/config details not visible in the implementation branch (`schedule`, `enrich`, `auth logout`, `OBSIDIAN_VAULT_PATH`, credentials JSON, callback port 8765). Verify before merging either branch. |
| Hive review status | README task is still uncertain | `.hive-state/stages/5-review/create-proper-readme-md-for-260513-2ba1/task.md` records `REVIEW_ERROR phase=fix reason=fix_failed pass=4`; latest worktree commits may or may not resolve that state. |
| Cross-project wiki | No xbookmark-specific master page found | `/home/asterio/wikis/master/wiki` exists, but `rg` found no `xbookmark`-specific page during refresh. |
| Verification | Tests were not rerun during wiki refresh | Source facts are read from code, git history, Hive state, and QMD search. Runtime behavior should still be verified in the implementation worktree before merge. |

## Resolved Bootstrap Validation

- 2026-05-14: Managed llm-wiki config, agent context, post-commit hook, and daily systemd timer were validated for `xbookmark`.
- 2026-05-14: `qmd update`, `qmd embed`, and collection-scoped `qmd search` passed for `xbookmark`. QMD tries GPU first and falls back to CPU on this host because Vulkan headers are missing.
- 2026-05-14: `qmd query` can still be slow under the sandboxed local-model path; use `qmd search` for maintenance checks and fall back to `rg` when semantic generation is too slow.
