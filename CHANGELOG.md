# Changelog

## Unreleased

- Reshape generated wiki output around readable source-note filenames, canonical concept pages, concept hierarchy links, and singleton-thread suppression.
- Add `xbookmark taxonomy audit` and `xbookmark taxonomy rebuild --apply` for offline graph cleanup with snapshots, manifests, graph-health reports, state path updates, and QMD reindexing.
- Re-root the QMD `bookmarks` collection at the bookmark wiki root so source notes, author pages, and concept pages are searchable.
- Enrichment now produces a concise `title`; bookmark filenames and graph labels derive from it instead of the full summary.
- Generate schema-2 frontmatter as queryable Obsidian Properties: typed `created_at`/`bookmarked_at` dates, a single semantic concept `kind`, and a kept `tags` keyword vocabulary (the empty `facets` key is dropped). `taxonomy rebuild --apply` migrates existing notes to schema 2 offline (no re-enrichment) and stops regenerating the synthetic `topics`/`entities` broader roots.
- Make scheduled taxonomy curation rollback-safe (atomic batch writes), fail the graph-health gate when legacy pages survive a repair, report a real-broader ratio, and retain only the most recent pre-apply snapshots.

## 0.2.4 - 2026-06-15

- Keep image-backed bookmark enrichment moving by falling back to text-only Codex when image handling returns a transient or schema-invalid response.
- Report retry rows that exhaust their budget as permanent errors while still stamping successful source-clean sync runs.

## 0.2.3 - 2026-06-15

- Report OAuth login callback timeouts and auth failures without a Ruby stack trace.

## 0.2.2 - 2026-06-15

- Report expired saved X OAuth access tokens from `auth status` with the exact expiry timestamp and next recovery command.
- Add `auth refresh` so saved refresh tokens can be tested and rotated directly.
- Redact token endpoint failures and avoid writing malformed refresh responses into local auth state.
- Keep transient X token refresh outages separate from permanent reauthorization failures.

## 0.2.1 - 2026-06-14

- Keep scheduled sync maintenance running when X auth, rate limits, or transport are unavailable.
- Cache source payloads in SQLite so pending and retryable bookmarks can still be enriched during source outages.
- Report source outages as `source blocked` instead of charging them to per-bookmark permanent failures.
- Bound QMD maintenance subprocesses and harden auth/source error handling for unattended scheduler runs.
- Refresh audited runtime dependencies used by the sync daemon.
