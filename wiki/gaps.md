# Wiki Gaps

| Area | Gap | Notes |
|------|-----|-------|
| Production backfill completeness | Production wiki still needs a backfill rerun with 50-item pages | `max_results=100` returned only 98 IDs with no `next_token`, while `max_results=50` returned 4,745 unique IDs across 95 pages. Code and docs now need to standardize on 50-item pages before rerunning production. |
| Cross-project wiki | No xbookmark-specific master page found | `/home/asterio/wikis/master/wiki` exists, but `rg` found no `xbookmark`-specific page during refresh. |

## Resolved Bootstrap Validation

- 2026-05-14: Managed llm-wiki config, agent context, post-commit hook, and daily systemd timer were validated for `xbookmark`.
- 2026-05-14: `qmd update`, `qmd embed`, and collection-scoped `qmd search` passed for `xbookmark`. QMD tries GPU first and falls back to CPU on this host because Vulkan headers are missing.
- 2026-05-14: `qmd query` can still be slow under the sandboxed local-model path; use `qmd search` for maintenance checks and fall back to `rg` when semantic generation is too slow.
- 2026-05-22: README command/config docs were reconciled to the implemented CLI so new setups do not follow unsupported `schedule`, `--config`, `auth refresh/logout`, `enrich`, or extra backfill/find flags.
- 2026-05-22: README Ruby version and contributor checks were reconciled to the gemspec and RSpec-based test suite.
- 2026-05-22: Scheduler installation is now part of the default setup flow, and QMD registration handles the current `qmd collection add` command shape.
- 2026-05-22: Runtime source, specs, CI config, and project wiki are now on `main`; the older "runtime not on main" gap is resolved.
- 2026-05-22: `.env.example` no longer references a nonexistent `auth login --port` option; setup uses `X_REDIRECT_URI`.
- 2026-05-22: Linux scheduler setup now tries to enable systemd linger automatically so daily timers can run after logout.
- 2026-05-22: Live production backfill exposed a Codex JSONL event-shape drift; `item.completed` agent messages are now parsed.
- 2026-05-22: Media download no longer has a default 200 MB cap; large X videos are allowed to download.
- 2026-05-22: Live OAuth, bookmark API, production scheduler, QMD, media, transcript, enrichment, and duplicate checks were validated against the production install. Durable lessons are captured in [[live-production-learnings]].
