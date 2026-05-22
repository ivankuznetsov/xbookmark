# xbookmark

Own your X bookmarks as a local, Obsidian-ready bookmark wiki with LLM enrichment and Whisper transcription.

xbookmark pulls your X (formerly Twitter) bookmarks through the official paid X API v2, writes each one to a plain markdown file with YAML frontmatter, runs an LLM enrichment pass for summaries and tags, and transcribes any linked audio or video locally with Whisper.

It is built for people who keep notes in Obsidian or any markdown-first system and are tired of X bookmarks being unsearchable and ephemeral. xbookmark writes to its own standalone bookmark wiki directory; point Obsidian at that folder when you want to browse it. Everything runs on your machine; nothing leaves it except the calls you authorize to the X API and your configured LLM provider.

<p align="center">
  <a href="https://github.com/ivankuznetsov/xbookmark/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/ivankuznetsov/xbookmark/ci.yml?branch=main&label=ci" alt="Build status"></a>
  <a href="#roadmap"><img src="https://img.shields.io/badge/gem-unreleased-lightgrey" alt="Gem version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License"></a>
  <img src="https://img.shields.io/badge/ruby-%E2%89%A5%203.3-red" alt="Ruby version">
</p>

<p align="center">
  <img src="docs/assets/demo.gif" alt="xbookmark backfill and find demo">
</p>

Clone, install dependencies, and copy the env template:

```bash
git clone https://github.com/ivankuznetsov/xbookmark.git
cd xbookmark
bundle install
cp .env.example .env
```

Stop here and edit `.env` to fill in `X_CLIENT_ID`, `X_USER_ID`, and `XBOOKMARK_WIKI_PATH` — see [Configuration → Set up X API access](#set-up-x-api-access) for how to obtain the X values. Then run:

```bash
bin/xbookmark auth login
bin/xbookmark backfill --limit 100
bin/xbookmark find 'rails'
```

Example `find` output:

```
bookmarks/2026/05/1789012345678901234.md  "Rails 8.0 ships with..."  @dhh
bookmarks/2026/04/1788123456789012345.md  "A small Rails tip..."     @rosa
```

## Quick install with an AI agent

If you use Claude Code, Cursor, Codex, ChatGPT, or any other AI assistant, paste the prompt below and let it install and configure xbookmark for you. Agents with shell access run the steps; chat-only agents walk you through them.

```text
Install and configure xbookmark from https://github.com/ivankuznetsov/xbookmark on this machine.

1. Read README.md from that repo and follow the Installation section that matches my operating system.
2. Follow the Configuration section: copy .env.example to .env, ask me for my X developer Client ID, numeric X user ID, and bookmark wiki path, and fill them in. Leave X_CLIENT_SECRET blank unless I say my X app is a confidential client.
3. Run `bin/xbookmark auth login` so I can sign in to X in my browser.
4. Ask me whether to install the daily scheduler (`bin/xbookmark schedule install --daily`).
5. Verify with `bin/xbookmark --version` and `bin/xbookmark auth status`, then report the output.

Stop and ask me before installing system packages with sudo, and before any step that would overwrite a file in my home directory.
```

If you prefer to run the steps yourself, jump to [Installation](#installation) and [Configuration](#configuration) below.

## Features

- One-shot backfill of your entire X bookmark history into a local bookmark wiki.
- Daily incremental ingest via a built-in scheduler (systemd or cron on Linux, launchd on macOS).
- Obsidian-friendly markdown output with YAML frontmatter and stable file naming.
- Full-text search over the bookmark wiki via a local QMD index (a markdown full-text search engine).
- LLM enrichment (summary, tags) via the [`codex`](https://github.com/openai/codex) CLI.
- Local Whisper transcription of audio and video linked from a bookmark.
- Official X API v2 only, via OAuth 2.0 with PKCE.
- MIT-licensed and runs entirely on your machine.

## Installation

xbookmark is installed from source. There is no published gem, AUR package, or Homebrew tap yet.

### Prerequisites

Every supported platform needs:

- Ruby 3.3 or newer.
- `ffmpeg` for media extraction.
- A Whisper backend — either `whisper.cpp` (the default, fast on CPU) or `faster-whisper` (Python, GPU-friendly).
- The [`codex` CLI](https://github.com/openai/codex) for LLM enrichment.
- `git`.

### Arch Linux

```bash
sudo pacman -S ruby ffmpeg sqlite base-devel git

# whisper.cpp: build from source (recommended below), or install the
# community-maintained AUR package `whisper.cpp-git` if you already have an
# AUR helper such as yay or paru set up.
git clone https://github.com/ggml-org/whisper.cpp.git && (cd whisper.cpp && make)

git clone https://github.com/ivankuznetsov/xbookmark.git
cd xbookmark
bundle install
bin/xbookmark --version
```

### Ubuntu / Debian

```bash
sudo apt install ruby ruby-dev build-essential libsqlite3-dev ffmpeg git

# Ubuntu 24.04 and earlier and Debian 12 ship a Ruby older than 3.3 (24.04
# packages Ruby 3.2.x). Install a modern Ruby with rbenv or mise if
# `ruby -v` reports < 3.3.

# whisper.cpp from source
git clone https://github.com/ggml-org/whisper.cpp.git && (cd whisper.cpp && make)

git clone https://github.com/ivankuznetsov/xbookmark.git
cd xbookmark
bundle install
bin/xbookmark --version
```

### Fedora

```bash
sudo dnf install ruby ruby-devel @development-tools sqlite-devel ffmpeg git

# whisper.cpp from source
git clone https://github.com/ggml-org/whisper.cpp.git && (cd whisper.cpp && make)

git clone https://github.com/ivankuznetsov/xbookmark.git
cd xbookmark
bundle install
bin/xbookmark --version
```

### macOS

```bash
brew install ruby ffmpeg sqlite git whisper-cpp

# If `ruby -v` still shows the system Ruby, prepend Homebrew's Ruby to PATH:
#   echo 'export PATH="$(brew --prefix ruby)/bin:$PATH"' >> ~/.zshrc

git clone https://github.com/ivankuznetsov/xbookmark.git
cd xbookmark
bundle install
bin/xbookmark --version
```

A published gem is on the [Roadmap](#roadmap); until then, clone-and-bundle is the supported install path.

## Configuration

xbookmark reads configuration from dotenv files. Resolution order is:
`--config PATH`, `XBOOKMARK_CONFIG`, `$PWD/.env`, then
`~/.config/xbookmark/.env`. Scheduled jobs are installed with an absolute
`--config` path so they do not depend on the scheduler's working directory.

Copy the example and fill in the values:

```bash
cp .env.example .env
```

### Configuration file

`.env.example` is the canonical key list. Keep real credentials only in
`.env` or another gitignored config file; do not edit `.env.example` with
secrets.

### Set up X API access

1. Sign in at the [X developer portal](https://developer.x.com) and create a project, then create an app inside it.
2. Enable OAuth 2.0 on the app. Set the callback URL to `http://127.0.0.1:8765/callback` for the default loopback port. If that port is permanently unavailable, register the port you will pass to `auth login --port PORT`; if you want automatic fallback ports to work, register those callback URLs too.
3. Request the v1 scope set: `bookmark.read`, `users.read`, `tweet.read`, and `offline.access`. `offline.access` is intentional because xbookmark stores a refresh token for scheduled jobs and explicit `auth refresh`.
4. Copy the Client ID into `X_CLIENT_ID` and your numeric X user ID into `X_USER_ID`. `X_CLIENT_SECRET` is only required if your app type is a confidential client that issues a secret; PKCE public-client apps leave it blank.
5. Run `bin/xbookmark auth login`. The CLI opens your browser, completes the PKCE handshake, and stores tokens in `~/.config/xbookmark/credentials.json`; the parent directory is mode `0700` and the credentials file is mode `0600`.

### What this will cost

xbookmark uses the official paid X API. The README intentionally uses the
fallback path for now because pricing is checked at the merge gate, when the
CLI is ready to ship. Before merging to `main`, fetch the current
[X developer portal product tiers](https://developer.x.com/en/portal/products)
and add a dated estimate for Basic-tier dollars per 1000 bookmarks; until
then, use the published rate and quota on that page for your own estimate.

### codex authentication

Install the [`codex` CLI](https://github.com/openai/codex), run `codex login` once, point `CODEX_PROFILE` at the profile you want xbookmark to use, and confirm with `codex whoami`.

### Whisper backend

Set `WHISPER_BACKEND` to either `whisper.cpp` (default, fast on CPU, one-time C++ build) or `faster-whisper` (Python, GPU-friendly) and ensure the matching backend is on your `PATH` — see [Prerequisites](#prerequisites). `WHISPER_MODEL` defaults to `base.en`; v1 accepts `tiny.en`, `base.en`, `small.en`, `medium.en`, `tiny`, `base`, `small`, `medium`, and `large-v3`.

### Bookmark wiki path

Set `XBOOKMARK_WIKI_PATH` to the directory where xbookmark should create its standalone bookmark wiki from X data. This runtime output is separate from this repository's `wiki/` project LLM wiki. Use an xbookmark-owned folder you will later open from Obsidian, not an existing general-purpose Obsidian vault. On first run xbookmark creates the directory if it is missing, including any missing parent directories, with mode `0755` so normal sync and group-readable wiki workflows keep working. Credentials stay separate under `~/.config/xbookmark` with owner-only permissions. If the bookmark wiki path already exists but is not a directory, xbookmark exits non-zero without modifying it. See [Obsidian integration](#obsidian-integration) for how to open it in Obsidian.

## Usage

### auth

Manage X API credentials.

```bash
bin/xbookmark auth login [--port PORT]  # browser PKCE flow, stores tokens locally
bin/xbookmark auth refresh              # refresh the access token explicitly
bin/xbookmark auth logout               # delete stored tokens
bin/xbookmark auth status               # show account and token expiry only
```

Example output:

```
Signed in as @ikuznetsov (id 1234567890). Access token expires in 1h 58m.
```

`auth login` tries loopback port `8765` first, then the next free port through
`8800`; pass `--port PORT` to force a registered callback port. `auth status`
is read-only: when the access token has lapsed, it reports the expired token
without refreshing it. Run `auth refresh` to exchange the stored refresh token
for a new access token. If the refresh token itself has been revoked or has
expired, `auth refresh` exits non-zero and prompts you to re-run `auth login`.

### backfill

Pull historical bookmarks into the bookmark wiki.

```bash
bin/xbookmark backfill [--limit N] [--since YYYY-MM-DD] [--dry-run] [--overwrite]
```

`--since` accepts an ISO-8601 calendar date (`YYYY-MM-DD`), interpreted in local time.

Example:

```bash
bin/xbookmark backfill --limit 100
```

Example output:

```
Fetched 100 bookmarks. Wrote 100 markdown files to ~/wikis/xbookmark/bookmarks/.
```

Backfill is idempotent by default. If `bookmarks/YYYY/MM/<id>.md` already
exists for a fetched bookmark ID, xbookmark skips that file so local edits are
preserved. Pass `--overwrite` to regenerate existing bookmark files from the X
API and current enrichment output.

### find

Full-text search across the bookmark wiki.

```bash
bin/xbookmark find '<query>' [--type lex|vec|hyde] [--limit N] [--json]
```

Example:

```bash
bin/xbookmark find 'rails'
```

Example output:

```
bookmarks/2026/05/1789012345678901234.md  "Rails 8.0 ships with..."  @dhh
bookmarks/2026/04/1788123456789012345.md  "A small Rails tip..."     @rosa
```

`find` searches the entire wiki, so matches can span multiple month partitions
in a single result set. The default `--type lex` sends a QMD lexical query:
whitespace separates required terms, quoted text is matched as a phrase, and
v1 does not support regex, prefix wildcards, or boolean operators. Use
`--type vec` for vector similarity against the literal query, or `--type hyde`
to ask QMD to synthesize a hypothetical answer before vector search.

With `--json`, stdout is a stable envelope:

```json
{
  "query": "rails",
  "type": "lex",
  "limit": 10,
  "results": [
    {
      "path": "bookmarks/2026/05/1789012345678901234.md",
      "bookmark_id": "1789012345678901234",
      "score": 0.92,
      "author": "@dhh",
      "url": "https://x.com/dhh/status/1789012345678901234",
      "bookmarked_at": "2026-05-12T19:22:10Z",
      "title": "Rails 8.0 ships with...",
      "snippet": "Rails 8.0 ships with Solid Cache..."
    }
  ]
}
```

### enrich

Run the LLM enrichment pass.

```bash
bin/xbookmark enrich [--bookmark ID | --all] [--force]
```

Provide exactly one of `--bookmark` (a single tweet ID) or `--all` (every bookmark in the bookmark wiki) — the two are mutually exclusive. `--force` re-runs enrichment on bookmarks that already have `enriched_at` set; without it, those bookmarks are skipped.

Example:

```bash
bin/xbookmark enrich --all
```

Example output:

```
Enriched 42 bookmarks. Skipped 8 (already enriched). 0 failures.
```

### schedule

Install, remove, or inspect the daily ingest job.

```bash
bin/xbookmark schedule install --daily [--at HH:MM] [--scheduler auto|launchd|systemd|cron] [--config PATH]
bin/xbookmark schedule uninstall
bin/xbookmark schedule status
```

`--daily` is the only v1 cadence; hourly and weekly schedules are deferred.
`--at` defaults to `09:00` local time. `--scheduler auto` selects launchd on
macOS, systemd user timers on Linux when available, and cron otherwise.

Example output on Linux with systemd:

```
Daily ingest installed (systemd user timer `xbookmark-daily.timer`). Next run: tomorrow at 09:00.
```

Example output on macOS:

```
Daily ingest installed (launchd agent `com.xbookmark.daily`). Next run: tomorrow at 09:00.
```

Example output on Linux without systemd (cron fallback):

```
Daily ingest installed (user crontab entry). Next run: tomorrow at 09:00.
```

See [Scheduling](#scheduling) for the per-OS artifact and log locations.

### Help

Every subcommand accepts `--help`. The top-level `bin/xbookmark --help` lists all subcommands and global flags.

## How it works

xbookmark talks to the X API v2 to fetch your bookmarks, writes each one as a markdown file with YAML frontmatter into its bookmark wiki, then runs an enrichment pass (LLM summaries and tags via the default `codex` driver) and, for any linked audio or video, a local Whisper transcription. A QMD index over the bookmark wiki gives you fast full-text search through `bin/xbookmark find`.

```text
X API v2 -> Ingest -> Enrich -> Bookmark wiki -> QMD index
              |          ^                              |
              +-> Whisper -+                           v
                  media                         bin/xbookmark find
```

## Obsidian integration

To open the bookmark wiki in Obsidian, choose "Open folder as vault" from the Obsidian launcher and pick the directory you configured as `XBOOKMARK_WIKI_PATH`. Bookmarks land under `bookmarks/YYYY/MM/<id>.md`, partitioned by `bookmarked_at`.

The graph view picks up wiki-links and tags from each bookmark's frontmatter, so re-tagging in `codex` enrichment automatically reshapes the graph.

A typical bookmark file looks like this:

```markdown
---
id: "1789012345678901234"
url: "https://x.com/dhh/status/1789012345678901234"
author: "@dhh"
created_at: "2026-05-12T08:14:00Z"
bookmarked_at: "2026-05-12T19:22:10Z"
enriched_at: "2026-05-12T19:23:01Z"
tags:
  - rails
  - framework
  - release-notes
---

> Rails 8.0 ships today. Solid Cache, Solid Queue, Solid Cable are all
> defaults now. Authentication generator. Propshaft by default.

### Summary

Release announcement for Rails 8.0. Highlights the Solid trio as new
defaults, a built-in authentication generator, and Propshaft replacing
Sprockets in new apps.
```

## Scheduling

xbookmark installs its own daily ingest job using the native scheduler on each OS, so you do not need a separate cron config file.

```bash
bin/xbookmark schedule install --daily
bin/xbookmark schedule install --daily --scheduler cron --config ~/.config/xbookmark/.env
bin/xbookmark schedule status
bin/xbookmark schedule uninstall
```

The installer writes a command that invokes `bin/xbookmark backfill` with an
absolute `--config` path. Scheduled backfill records the last successful
scheduled run in xbookmark state and uses that date as the next run's
`--since` value. Overlap is safe because `backfill` skips existing bookmark
files unless `--overwrite` is passed.

Scheduler selection is `auto` by default: macOS uses launchd, Linux uses a
systemd user timer when `systemctl --user` is available, and Linux falls back
to cron otherwise. Pass `--scheduler launchd`, `--scheduler systemd`, or
`--scheduler cron` to force one backend.

The artifact written depends on your OS:

| OS | Artifact | Logs |
| --- | --- | --- |
| macOS | `~/Library/LaunchAgents/com.xbookmark.daily.plist` | `~/Library/Logs/xbookmark.log` |
| Linux (systemd) | `~/.config/systemd/user/xbookmark-daily.{service,timer}` | `journalctl --user -u xbookmark-daily` |
| Linux (no systemd) | A user crontab entry calling `bin/xbookmark backfill` | `~/.local/state/xbookmark/cron.log` |

If the X token refresh fails during a scheduled run, the job exits non-zero and logs the failure to the OS log destination above (journalctl for systemd, `cron.log` for cron, `xbookmark.log` for launchd). Re-run `bin/xbookmark auth login` to re-issue the refresh token.

`bin/xbookmark schedule uninstall` removes whichever artifact was created on this machine. Log files are preserved.

## FAQ

**How much will this cost?**
xbookmark uses the official paid X API; see [What this will cost](#what-this-will-cost) in Configuration. Local LLM enrichment and Whisper transcription are free per-call, but you pay for whatever provider you point `codex` at.

**Whisper transcription is slow.**
The default is `WHISPER_MODEL=base.en`. Switch to a smaller accepted model such as `tiny.en`, or switch backend to `faster-whisper` and run it on a GPU. The [whisper.cpp build docs](https://github.com/ggml-org/whisper.cpp#quick-start) cover Metal, CUDA, and OpenBLAS acceleration.

**codex auth expired.**
Run `codex login` again, then re-run `bin/xbookmark enrich --all` — bookmarks left without `enriched_at` will be retried on the next pass.

**X API rate-limited me.**
`backfill` respects the published `bookmark.read` rate limits but a long backfill can still hit the current rate-limit window. Lower `--limit` and re-run later, or schedule a daily ingest instead. The X API [rate-limit reference](https://docs.x.com/x-api/fundamentals/rate-limits) on `docs.x.com` lists the current numbers.

**Where are my markdown files?**
Under `$XBOOKMARK_WIKI_PATH/bookmarks/YYYY/MM/<id>.md`. The `bin/xbookmark find` output prints these paths so you can open them in your editor directly, or `cd "$(dirname …)"` into the containing folder.

**Why does xbookmark use `~/.config` on every OS?**
Credentials intentionally live at `~/.config/xbookmark/credentials.json` on both Linux and macOS so clone-and-bundle installs, scheduled jobs, and support docs share one path. Scheduler artifacts still use native OS locations; the credentials directory stays owner-only (`0700`) and the file stays `0600`.

## Roadmap

No commitments, no timeline — just the directions I expect to take next.

- Publish as a RubyGem so installation is `gem install xbookmark`.
- Ship an AUR package for Arch users.
- Ship a Homebrew tap for macOS users.
- Add Threads and Bluesky as adjacent bookmark providers.
- Encrypt the stored credentials file at rest.
- Expose a plugin API for custom enrichers (translation, sentiment, fact-check).

## Contributing

Dev setup is the same as a user install: `git clone`, `bundle install`, `cp .env.example .env`, and confirm with `bin/xbookmark --version`.

Tests run with `bundle exec rake test`. The default suite uses minitest. Integration tests replay VCR-style cassettes by default; to regenerate them against the real X API, run `RECORD=1 bundle exec rake test` with a working `.env`. Routine contributor test runs do not hit the X API.

Pull requests should be small and focused — one logical change per PR — and pass `bundle exec rake test`, `bundle exec rubocop`, and `bundle exec brakeman` before pushing. Link any related issue in the PR description.

## Credits

xbookmark builds on the [`codex`](https://github.com/openai/codex) CLI for enrichment, [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and [faster-whisper](https://github.com/SYSTRAN/faster-whisper) for local transcription, QMD for markdown search, [Obsidian](https://obsidian.md) for browsing the bookmark wiki, and the official X API.

## Security

Please report security issues privately to <ivan@ikuznetsov.com> rather than opening a public GitHub issue. I aim to acknowledge reports within 3 business days and coordinate a fix and disclosure timeline from there.

## License

MIT, Copyright (c) 2026 Ivan Kuznetsov. See [LICENSE](LICENSE) for the full text.
