# Changelog

## 0.2.1 - 2026-06-14

- Keep scheduled sync maintenance running when X auth, rate limits, or transport are unavailable.
- Cache source payloads in SQLite so pending and retryable bookmarks can still be enriched during source outages.
- Report source outages as `source blocked` instead of charging them to per-bookmark permanent failures.
- Bound QMD maintenance subprocesses and harden auth/source error handling for unattended scheduler runs.
- Refresh audited runtime dependencies used by the sync daemon.

