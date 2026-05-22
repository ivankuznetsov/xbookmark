---
title: Live Production Learnings
type: learnings
source: production setup/backfill run; X API probes; QMD checks; PRs 10-12
created: 2026-05-22
updated: 2026-05-22
tags: [learnings, production, backfill, x-api, whisper, qmd]
---

**TLDR**: The production run proved the pipeline works for every bookmark the X API exposes, but also surfaced several setup, media, enrichment, and search assumptions that needed hardening before new installs can be trusted.

## Most Important Findings

1. **The 100-bookmark target is source-data limited, not a pipeline bug.**
   The X bookmarks endpoint accepts `max_results` only in the range `1..100`; `max_results=200` is rejected. More than 100 bookmarks requires `meta.next_token` pagination. The live account currently returns one page with 98 unique bookmark IDs and no `next_token`, and bookmark folders return zero folders. The production wiki has 99 done bookmarks because one previously ingested bookmark no longer appears in the live bookmark list.

2. **Fresh setup docs must match implemented commands exactly.**
   The README originally drifted toward commands that did not exist, such as `schedule install` and `auth login --port`. New setup should use `bin/xbookmark install`, `X_REDIRECT_URI`, `XBOOKMARK_WIKI_PATH`, and `XBOOKMARK_ENV_FILE`. Keep the runtime bookmark wiki separate from this repository's project LLM wiki.

3. **X auth configuration needs `X_USER_ID` before useful sync commands can run.**
   OAuth login needs `X_CLIENT_ID` and callback settings, but the bookmark endpoint also needs the numeric authenticated user ID. Inspect `Config` requirements before running auth or sync during manual installs.

4. **Codex JSONL output shape is not stable enough to parse narrowly.**
   Current `codex exec --json` can put the final answer under `item.completed` events with an `agent_message` item. The parser needs to accept that shape as well as older model-message/plain JSON shapes.

5. **Aux-page summaries were the main avoidable backfill cost.**
   Author/topic/entity/thread landing pages are useful for Obsidian graph navigation, but separate LLM summaries for each slug created hundreds of extra Codex calls during a small production backfill. The durable default is to always write aux pages, but make separate aux summaries opt-in with `XBOOKMARK_AUX_SUMMARIES=true`.

6. **The enrichment hot path should avoid a planning LLM call.**
   Running a separate Codex planning call per bookmark made backfill slower without enough value. The production path now fetches allowed external article links directly and uses a final enrichment call.

7. **X media can be large and should not have a small default cap.**
   Real bookmarked videos exceeded the old 200 MB download limit. Full-size media downloads are required for fidelity; size limits should be explicit configuration, not an implicit default.

8. **whisper.cpp needs audio extraction, model alias resolution, and long-video timeouts.**
   Passing MP4 files directly to `whisper-cli` produced empty transcripts because whisper.cpp only supports audio formats such as WAV/MP3/FLAC/OGG. The stable path is: resolve `WHISPER_MODEL=base.en` to `ggml-base.en.bin`, extract audio with `ffmpeg`, treat no-audio MP4s as empty transcripts, scale timeouts by media duration, and run whisper.cpp with a practical thread count.

9. **Transcript sidecars alone are not enough after a repair run.**
   If transcript sidecars are regenerated after markdown was already rendered, the affected bookmark markdown must also get `## Transcript` sections. Otherwise the data exists on disk but not in the Obsidian-facing note.

10. **QMD command and output behavior must be guarded locally.**
    Current QMD uses `qmd collection list` / `qmd collection add`; older command shapes need fallbacks. `qmd query --limit 3` returned four results in production, so xbookmark caps parsed results itself. QMD also writes local cache/embedding state, so search/index verification may fail in read-only sandboxes.

11. **Reruns are idempotent for bookmarks.**
    SQLite uses `tweet_id` as the primary key, pending inserts use `INSERT OR IGNORE`, done bookmarks are skipped, markdown paths are deterministic, and media directories are replaced on reprocess. Production verification found 99 DB rows, 99 distinct markdown tweet IDs, and no duplicate bookmarks.

12. **Scheduler verification is part of production readiness.**
    The installed Linux unit is `xbookmark-sync.timer`, not `xbookmark.timer`. It points at the production `.env` and runs `bin/xbookmark sync --from-scheduler` daily. `sync --from-scheduler` should skip cleanly when the recent-run guard applies.

## Production Verification Snapshot

Last verified on 2026-05-22:

- Production checkout: `/home/asterio/Dev/xbookmark.install/xbookmark`, `main` at `3e6bbb0`.
- Runtime bookmark wiki: `/home/asterio/xbookmark-wiki`.
- X source: 98 live bookmark IDs, one page, no `next_token`, no bookmark folders.
- Local state: 99 bookmark rows, all `done`, zero stored errors.
- Markdown: 99 bookmark files, 99 distinct frontmatter `tweet_id`s, no duplicate bookmark notes.
- Aux pages: 91 authors, 440 topics, 335 entities, 99 threads.
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
