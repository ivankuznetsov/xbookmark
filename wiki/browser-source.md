---
title: Browser Bookmark Source
type: feature
source: lib/xbookmark/browser/*, lib/xbookmark/sources/factory.rb, lib/xbookmark/config.rb, lib/xbookmark/sync/runner.rb, lib/xbookmark/notify.rb
created: 2026-06-17
updated: 2026-06-18
tags: [browser, source, ferrum, graphql, parity]
---

**TLDR**: An opt-in `browser` source ingests your own X bookmarks via a real
Chromium (Ferrum) reading X's internal GraphQL, normalized into the **same API
v2 envelope** the existing pipeline already consumes — so media, quoted tweets,
transcripts, enrichment, and QMD all work unchanged. Selected with
`XBOOKMARK_SOURCE`; coexists with the API source.

## Why

The official X path needs the paid developer API. The browser source lets a user
ingest their own bookmarks by logging into X in a real browser once, with no dev
API credentials. ToS/account-risk is accepted via a one-time consent prompt.

## Central design idea — parity by envelope reuse

`Xbookmark::X::Expansions` already turns an X API v2 JSON envelope
(`{"data":[…],"includes":{users,media,tweets},"meta":{next_token}}`) into rich
`Bookmark` structs, and everything downstream consumes only that. So the browser
source's whole job is to **normalize X's internal GraphQL `Bookmarks` responses
into that exact envelope**. Achieve that and full fidelity (media variants,
quoted/referenced tweets, `conversation_id`, entity urls, author handle/name)
follows with **zero** changes to the pipeline, renderer, downloader, whisper, or
enrichment. `Browser::Normalizer` is that transform; it is covered by committed
GraphQL fixtures and an AC4 round-trip parity test against the API-path fixture.

## Central design idea — sources are duck-typed

`Sync::Runner` drives sources through a narrow contract:
`bookmarks(user_id:, max_results:) { |envelope| }` yielding API-v2 page
envelopes, and `get_tweet(id)` returning a single-tweet API-v2 payload.
`X::Client` is the API source; `Browser::Source` is a second object with the
same two methods. The Runner was generalized from a single `x_client:` to an
ordered `sources:` list (with a back-compat `x_client:` shim), so a configured
API source keeps syncing in the same run even when the browser session expired.

## Components (`lib/xbookmark/browser/`)

- `Chromium` — detect a system Chromium/Chrome (PATH + macOS `/Applications`).
  Required but **never bundled**; this is the single source of truth.
- `Session` — wraps Ferrum: detected Chromium + an isolated persistent profile
  (`~/.config/xbookmark/browser-profile`, never the everyday profile), headed for
  login / headless for sync, `with_page`/`open_page`/`logged_in?`. The real
  `Ferrum::Browser` is reached only through a one-line seam so tests never launch
  Chromium and the 100% coverage gate holds.
- `GraphqlCapture` — dedupes and parses Bookmarks/tweet GraphQL response bodies
  from the page's CDP network traffic. The page issues authentic requests
  (driven by scrolling); no header/transaction-id forgery.
- `Normalizer` — pure GraphQL → API v2 envelope transform (the parity core).
- `Source` — implements the source contract; scrolls to paginate, yields
  normalized envelopes until the cursor stops advancing; raises
  `SessionExpired` on a login/checkpoint redirect.
- `Login` — one-time consent prompt + headed login, polling until authenticated;
  consent persisted in the `State::Store` meta table (`browser_consent_at`).
- `SessionExpired < Xbookmark::AuthError` — caught by the Runner's existing
  `rescue Xbookmark::AuthError`, but distinguishable for re-login signaling.

## Configuration & CLI

- `XBOOKMARK_SOURCE=api` (default) `| browser | both`. In `browser` mode the
  `X_*` keys are optional (`Config#validate_required!` is conditional).
- `Sources::Factory.build(config:, store:)` returns the ordered source list;
  for `both` the API source is first.
- `auth login --browser` runs the headed login; `auth status` reports the active
  source and browser-session presence; `doctor` reports Chromium, profile dir,
  and saved-session state. None of these launch a browser except the login.

## Unattended expiry (AC3)

On a scheduled headless run, a `SessionExpired` is recorded via the parameterless
`report.mark_session_expired` (the browser is the only source that raises it) —
the only writer of the read-only `expired_source` field (`report.expired_source =
…` would raise, by design), from which `report.session_expired?` derives;
`source_errors` is also bumped.
This is isolated on every path — sync, retry, **and resync** — via
`source_blocked`. The CLI then fires `Notify.deliver` (notify-send on Linux,
osascript on macOS; spawned detached so a stuck D-Bus can't hang the run),
emits a grep-able `SESSION_EXPIRED source=<name>` stderr token, and exits
**non-zero even under `--from-scheduler`** — the one source-block case that is
intentionally noisy, distinct from the API-token-block degrade-to-exit-0 path.
A co-configured API source still completes the same run.

## Testing note (CI vs. live X)

The live browser→X path cannot run in CI (no provisionable X account, anti-bot),
so AC1–AC4 are validated by a **local manual acceptance run**, while the
deterministic units (normalizer via committed real-shape fixtures, source
selection, config gating, notify, expiry signaling, consent, Chromium
detection) carry full automated coverage to keep the 100% gate green. See
[[gaps]] and [[live-production-learnings]].

Related: [[architecture]], [[api]], [[commands]], [[dependencies]], [[decisions]], [[data-model]], [[gaps]], [[live-production-learnings]].
