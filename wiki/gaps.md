# Wiki Gaps

| Area | Gap | Notes |
|------|-----|-------|
| Main branch coverage | Runtime source is not on `main` | `main` historically tracked only `.gitignore` and `LICENSE`; the active PR carries the runtime CLI, README, and wiki-path configuration changes. |
| Live X verification | OAuth and bookmark API paths need real credentials | Tests cover PKCE/token behavior with stubs, but a full new setup still needs `X_CLIENT_ID`, `X_USER_ID`, and browser login against X. |
| Cross-project wiki | No xbookmark-specific master page found | `/home/asterio/wikis/master/wiki` exists, but `rg` found no `xbookmark`-specific page during refresh. |

## Resolved Bootstrap Validation

- 2026-05-14: Managed llm-wiki config, agent context, post-commit hook, and daily systemd timer were validated for `xbookmark`.
- 2026-05-14: `qmd update`, `qmd embed`, and collection-scoped `qmd search` passed for `xbookmark`. QMD tries GPU first and falls back to CPU on this host because Vulkan headers are missing.
- 2026-05-14: `qmd query` can still be slow under the sandboxed local-model path; use `qmd search` for maintenance checks and fall back to `rg` when semantic generation is too slow.
- 2026-05-22: README command/config docs were reconciled to the implemented CLI so new setups do not follow unsupported `schedule`, `--config`, `auth refresh/logout`, `enrich`, or extra backfill/find flags.
- 2026-05-22: README Ruby version and contributor checks were reconciled to the gemspec and RSpec-based test suite.
- 2026-05-22: Scheduler installation is now part of the default setup flow, and QMD registration handles the current `qmd collection add` command shape.
