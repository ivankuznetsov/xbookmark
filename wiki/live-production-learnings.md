---
title: Live Production Learnings
type: learnings
source: production setup/backfill run; X API probes; QMD checks; PRs 10-12; Codex service-tier setup fix
created: 2026-05-22
updated: 2026-05-25
tags: [learnings, production, backfill, x-api, whisper, qmd, codex]
---

**TLDR**: The production run proved the pipeline works for every bookmark the X API exposes, but also surfaced several setup, media, enrichment, and search assumptions that needed hardening before new installs can be trusted.

## Most Important Findings

1. **Use 50-item bookmark pages, not 100-item pages.**
   The X bookmarks endpoint rejects `max_results=200`, but `max_results=100` is not reliable in production: it returned one page with 98 unique IDs and no `next_token`. The same live account with `max_results=50` returned 95 pages, 4,745 unique IDs, and tweets back to 2019-12-10. More than 100 bookmarks works by following `meta.next_token`, and xbookmark now requests 50 per page.

2. **Fresh setup docs must match implemented commands exactly.**
   The README originally drifted toward commands that did not exist, such as `schedule install` and `auth login --port`. New setup should use `bin/xbookmark install`, `X_REDIRECT_URI`, `XBOOKMARK_WIKI_PATH`, and `XBOOKMARK_ENV_FILE`. Keep the runtime bookmark wiki separate from this repository's project LLM wiki.

3. **X auth configuration needs `X_USER_ID` before useful sync commands can run.**
   OAuth login needs `X_CLIENT_ID` and callback settings, but the bookmark endpoint also needs the numeric authenticated user ID. Inspect `Config` requirements before running auth or sync during manual installs.

4. **Codex JSONL output shape is not stable enough to parse narrowly.**
   Current `codex exec --json` can put the final answer under `item.completed` events with an `agent_message` item. The parser needs to accept that shape as well as older model-message/plain JSON shapes.

5. **Aux-page summaries were the main avoidable backfill cost.**
   Author and concept landing pages are useful for Obsidian graph navigation, but separate LLM summaries for every generated page created hundreds of extra Codex calls during a small production backfill. The durable default is to always write author/concept pages, suppress singleton thread pages, and make separate author summaries opt-in with `XBOOKMARK_AUX_SUMMARIES=true`.

6. **The enrichment hot path should avoid a planning LLM call.**
   Running a separate Codex planning call per bookmark made backfill slower without enough value. The production path now fetches allowed external article links directly and uses a final enrichment call.

7. **X media can be large and should not have a small default cap.**
   Real bookmarked videos exceeded the old 200 MB download limit. Full-size media downloads are required for fidelity; size limits should be explicit configuration, not an implicit default.

8. **whisper.cpp needs audio extraction, model alias resolution, and long-video timeouts.**
   Passing MP4 files directly to `whisper-cli` produced empty transcripts because whisper.cpp only supports audio formats such as WAV/MP3/FLAC/OGG. The stable path is: resolve `WHISPER_MODEL=base.en` to `ggml-base.en.bin`, extract audio with `ffmpeg`, treat no-audio MP4s as empty transcripts, scale timeouts by media duration, and run whisper.cpp with a practical thread count.

9. **Transcript sidecars alone are not enough after a repair run.**
   If transcript sidecars are regenerated after markdown was already rendered, the affected bookmark markdown must also get `## Transcript` sections. Otherwise the data exists on disk but not in the Obsidian-facing note. Future enrichment should also summarize transcripts and format evident speaker turns instead of dumping raw Whisper text.

10. **QMD command and output behavior must be guarded locally.**
    Current QMD uses `qmd collection list` / `qmd collection add`; older command shapes need fallbacks. `qmd query --limit 3` returned four results in production, so xbookmark caps parsed results itself. QMD also writes local cache/embedding state, so search/index verification may fail in read-only sandboxes.

11. **Reruns are idempotent for bookmarks.**
    SQLite uses `tweet_id` as the primary key, pending inserts use `INSERT OR IGNORE`, done bookmarks are skipped, markdown paths are deterministic, and media directories are replaced on reprocess. Production verification found 99 DB rows, 99 distinct markdown tweet IDs, and no duplicate bookmarks.

12. **Scheduler verification is part of production readiness.**
    The installed Linux unit is `xbookmark-sync.timer`, not `xbookmark.timer`. It points at the production `.env` and runs `bin/xbookmark sync --from-scheduler` daily. `sync --from-scheduler` should skip cleanly when the recent-run guard applies. Incremental sync should start at the newest bookmark page and stop after a fully known page; X `next_token` values are page-traversal tokens, not durable cursors for future syncs.

13. **Do not force Codex service tiers in user setup.**
    A stale top-level `service_tier = "default"` in Codex config broke production wiki maintenance, and forcing Codex fast/flex modes would make scheduled enrichment cost behavior surprising. The setup path should remove stale invalid top-level service-tier values while preserving intentional valid speed modes.

14. **Large enrichment prompts must go through stdin, not argv.**
    A long production bookmark with media/transcript context hit `Errno::E2BIG: Argument list too long - codex` because the full prompt was passed as a command argument to `codex exec`. The stable invocation is `codex exec --json -- -` with the prompt written to stdin, while images stay as discrete `--image` arguments.

## Production Verification Snapshot

Last verified on 2026-05-22:

- Production checkout: `/home/asterio/Dev/xbookmark.install/xbookmark`, `main` at `3e6bbb0`.
- Runtime bookmark wiki: `/home/asterio/xbookmark-wiki`.
- X source: 4,745 live bookmark IDs over 95 pages with `max_results=50`; `max_results=100` returned only 98 IDs and no `next_token`.
- Local state: 99 bookmark rows, all `done`, zero stored errors before rerunning backfill with the corrected page size.
- Markdown: 99 bookmark files, 99 distinct frontmatter `tweet_id`s, no duplicate bookmark notes.
- Legacy snapshot before taxonomy rebuild: 91 authors, 440 topics, 335 entities, 99 threads. New output writes canonical `concepts/` pages instead of topic/entity graph pages.
- Media/transcripts: 20 MP4 files, 20 transcript sidecars, 18 non-empty transcripts, 2 no-audio MP4s, 18 markdown transcript sections.
- QMD: `bookmarks` collection has 99 files; `qmd embed` completed after transcript updates; `bin/xbookmark find Transcript --limit 3` returns exactly three results.
- Scheduler: `xbookmark-sync.timer` active and enabled, triggering `xbookmark-sync.service`.

## Reusable Verification Commands

Use these from the production checkout with `XBOOKMARK_ENV_FILE` pointing at the production env file:

```bash
env XBOOKMARK_ENV_FILE=/home/asterio/Dev/xbookmark.install/xbookmark/.env bin/xbookmark doctor
env XBOOKMARK_ENV_FILE=/home/asterio/Dev/xbookmark.install/xbookmark/.env bin/xbookmark backfill --limit 100
sqlite3 /home/asterio/xbookmark-wiki/.xbookmark/state.db "select count(*) from bookmarks; select status,count(*) from bookmarks group by status;"
find /home/asterio/xbookmark-wiki/bookmarks -type f -name '*.md' | wc -l
find /home/asterio/xbookmark-wiki/media -type f -name '*.mp4.transcript.txt' -size +0c | wc -l
env XBOOKMARK_ENV_FILE=/home/asterio/Dev/xbookmark.install/xbookmark/.env bin/xbookmark find Transcript --limit 3
systemctl --user status xbookmark-sync.timer --no-pager --lines=20
```

Related: [[architecture]], [[api]], [[commands]], [[data-model]], [[dependencies]], [[decisions]], [[gaps]].
