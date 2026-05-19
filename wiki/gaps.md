# Wiki Gaps

| Area | Gap | Notes |
|------|-----|-------|
| Main branch coverage | Runtime source is not on `main` | `main` tracks only `.gitignore` and `LICENSE`; architecture, commands, dependencies, and data-model pages document unmerged Hive worktrees and say so explicitly. |
| Command reconciliation | README/spec branch and implementation branch may drift | README branch now documents `schedule`, `enrich`, `auth refresh`, `auth logout`, `backfill --since/--dry-run/--overwrite`, `find --type`, `find --json`, and `--config`; implementation branch exposes `install`, `sync`, `resync`, `doctor`, `auth login/status`, `backfill --limit`, and `find --limit`. |
| Config reconciliation | README config keys differ from implementation config keys | README branch documents `XBOOKMARK_CONFIG`, `OBSIDIAN_VAULT_PATH`, `CODEX_PROFILE`, and credentials JSON. Implementation branch reads `XBOOKMARK_ENV_FILE`, `XBOOKMARK_VAULT`, `CODEX_BIN`, `QMD_BIN`, env-file tokens, and default XDG/macOS paths. |
| OAuth reconciliation | README callback and token-storage claims differ from implementation | README/.env.example use callback port 8765 and describe `auth login --port` fallback to 8800 plus `~/.config/xbookmark/credentials.json`; implementation default is `Auth::LOCAL_PORT = 7799`, derives the port from `X_REDIRECT_URI`, and writes tokens into the env file. |
| Scheduler reconciliation | README schedule command differs from implementation scheduler | README documents `schedule install/status/uninstall`, cron fallback, and scheduled `backfill` with an absolute `--config`; implementation exposes `install --time/--dry-run/--uninstall`, chooses only systemd or launchd, and scheduled artifacts run `sync --from-scheduler`. |
| Data layout reconciliation | README vault paths differ from implementation renderer paths | README examples use `bookmarks/YYYY/MM/<id>.md`; implementation renderer writes `bookmarks/YYYY/MM/DD/<tweet_id>.md`. |
| Dependency/doc reconciliation | README prerequisites and contributor checks are ahead of manifests read | README says Ruby `>= 3.3` and contributor checks include `rubocop` and `brakeman`; implementation gemspec says Ruby `>= 3.1`, and the Gemfile read only includes `rspec`, `webmock`, and `rake` in development/test. |
| Hive review status | README task hit a fix-guardrail wait after pass 4 | The guardrail flagged executable-mode restorations from managed `.llm-wiki` scripts in the fix commit; the PR diff against `main` did not add executable files. Verify final Hive state before treating the README branch as approved. |
| Cross-project wiki | No xbookmark-specific master page found | `/home/asterio/wikis/master/wiki` exists, but `rg` found no `xbookmark`-specific page during refresh. |
| Verification | Tests were not rerun during wiki refresh | Source facts are read from code, git history, Hive state, README diff, and relevant source files. Runtime behavior should still be verified in the implementation worktree before merge. |

## Resolved Bootstrap Validation

- 2026-05-14: Managed llm-wiki config, agent context, post-commit hook, and daily systemd timer were validated for `xbookmark`.
- 2026-05-14: `qmd update`, `qmd embed`, and collection-scoped `qmd search` passed for `xbookmark`. QMD tries GPU first and falls back to CPU on this host because Vulkan headers are missing.
- 2026-05-14: `qmd query` can still be slow under the sandboxed local-model path; use `qmd search` for maintenance checks and fall back to `rg` when semantic generation is too slow.
