# Wiki Gaps

| Area | Gap | Notes |
|------|-----|-------|
| Production backfill completeness | Production wiki still needs a backfill rerun with 50-item pages | Code and docs now standardize on 50-item bookmark pages. The remaining uncertainty is production data completeness after rerunning against the 4,745 IDs found by the read-only probe. |
| Codex service-tier cleanup | Needs live setup/install verification after commit | Current code removes stale invalid top-level `service_tier` values, preserves valid speed modes, and specs cover parser/setup/install/atomic-write paths, but this refresh did not run a real setup/install against a user's live Codex config. |
| Provider auth live backend verification | Public auth routing is implemented and documented, but recent wiki refreshes did not exercise real host credential stores | Source and tests cover `auth login PROVIDER`, `auth bind`, `auth list`, `auth show`, `auth rm`, resolver priority, and integration plumbing with shimmed `secret-tool`/`op`; a live macOS Keychain, Linux libsecret, or 1Password CLI smoke run was not performed here. |
| Cross-project wiki | No xbookmark-specific master page found | `/home/asterio/wikis/master/wiki` exists, but 2026-05-30 searches found no `xbookmark`-, `tomlrb`-, `AuthConfig`-, or `auth.toml`-specific page. `~/wikis/main/wiki`, `../wikis/master/wiki`, and `../wikis/main/wiki` did not exist. |
| Keychain not-found exit codes | The "non-zero + empty stderr ⇒ absent" heuristic in the keychain backends assumes, but has not verified against the real tools, which exit codes mean "item not found" | `keychain.rb`/`libsecret.rb` now treat a nil `exitstatus` (signal kill) as a hard error rather than "absent", and `Libsecret#delete` tolerates a non-zero-with-empty-stderr clear as "already gone" (mirroring `Keychain#delete`'s exit-44 handling). The precise `secret-tool`/`security` not-found exit codes were inferred from behaviour, not confirmed from a live run; a real-backend smoke test could pin them. |
| Worktree git status integrity | Current refresh could not use full status/cached-diff checks because the shared worktree index references missing blobs | On 2026-05-30, `git status --short` and `git diff --cached --name-only` failed on missing blob `26d9b9b4b284d58add70f2ed2d581a1ab503fa67` for `plugins/hugging-face/skills/community-evals/examples/.env.example`; `git log`, `git show`, source reads, and unstaged name-only diff still worked. Repair the object store or use a fresh worktree before treating status-based cleanliness as authoritative. |

## Resolved Bootstrap Validation

- 2026-05-14: Managed llm-wiki config, agent context, post-commit hook, and daily systemd timer were validated for `xbookmark`.
- 2026-05-14: `qmd update`, `qmd embed`, and collection-scoped `qmd search` passed for `xbookmark`. QMD tries GPU first and falls back to CPU on this host because Vulkan headers are missing.
- 2026-05-14: `qmd query` can still be slow under the sandboxed local-model path; use `qmd search` for maintenance checks and fall back to `rg` when semantic generation is too slow.
- 2026-05-22: README command/config docs were reconciled to the implemented CLI so new setups do not follow unsupported `schedule`, `--config`, `auth refresh/logout`, `enrich`, or extra backfill/find flags.
- 2026-05-22: README Ruby version and contributor checks were reconciled to the gemspec and then-current test suite.
- 2026-05-25: Test suite, CI, README, and dependency notes now use Minitest with fixture-backed data and the 100% coverage gate.
- 2026-05-30: Dependency coverage now records the `tomlrb` runtime dependency, `AuthConfig`'s `auth.toml` artifact, credential-store external tools, and public provider auth-routing commands. Live host credential-store smoke testing remains a separate gap.
- 2026-05-22: Scheduler installation is now part of the default setup flow, and QMD registration handles the current `qmd collection add` command shape.
- 2026-05-22: Runtime source, specs, CI config, and project wiki are now on `main`; the older "runtime not on main" gap is resolved.
- 2026-05-22: `.env.example` no longer references a nonexistent `auth login --port` option; setup uses `X_REDIRECT_URI`.
- 2026-05-22: Linux scheduler setup now tries to enable systemd linger automatically so daily timers can run after logout.
- 2026-05-22: Live production backfill exposed a Codex JSONL event-shape drift; `item.completed` agent messages are now parsed.
- 2026-05-22: Media download no longer has a default 200 MB cap; large X videos are allowed to download.
- 2026-05-22: Live OAuth, bookmark API, production scheduler, QMD, media, transcript, enrichment, and duplicate checks were validated against the production install. Durable lessons are captured in [[live-production-learnings]].
- 2026-05-25: `bundle exec rake coverage` is now the local 100% line-coverage gate for `bin/` and `lib/`; last recorded pass was 301 runs and 1053 assertions at 100.00% (2297/2297).
