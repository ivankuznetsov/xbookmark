# xbookmark

Own your X bookmarks as a local, Obsidian-ready markdown vault with LLM enrichment and Whisper transcription.

xbookmark pulls your X (formerly Twitter) bookmarks through the official paid X API v2, writes each one to a plain markdown file with YAML frontmatter, runs an LLM enrichment pass for summaries and tags, and transcribes any linked audio or video locally with Whisper.

It is built for people who keep notes in Obsidian or any markdown-first system and are tired of X bookmarks being unsearchable and ephemeral. Everything runs on your machine; nothing leaves it except the calls you authorise to the X API and your configured LLM provider.

<p align="center">
  <a href="#roadmap"><img src="https://img.shields.io/badge/ci-pending-lightgrey" alt="Build status"></a>
  <a href="#roadmap"><img src="https://img.shields.io/badge/gem-unreleased-lightgrey" alt="Gem version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License"></a>
  <img src="https://img.shields.io/badge/ruby-%E2%89%A5%203.3-red" alt="Ruby version">
</p>

<p align="center">
  <img src="docs/assets/demo.gif" alt="xbookmark backfill and find demo">
</p>

Before running `auth login`, complete [Configuration → Set up X API access](#set-up-x-api-access) to obtain an `X_CLIENT_ID`.

```bash
git clone https://github.com/ivankuznetsov/xbookmark.git
cd xbookmark
bundle install
cp .env.example .env   # then fill in X_CLIENT_ID — see Configuration
bin/xbookmark auth login
bin/xbookmark backfill --limit 100
bin/xbookmark find 'rails'
```

## Features

- One-shot backfill of your entire X bookmark history into a local markdown vault.
- Daily incremental ingest via a built-in scheduler (systemd or cron on Linux, launchd on macOS).
- Obsidian-friendly markdown output with YAML frontmatter and stable file naming.
- Full-text search over the vault via a local QMD index (a markdown full-text search engine).
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
git clone https://github.com/ggerganov/whisper.cpp.git && (cd whisper.cpp && make)

git clone https://github.com/ivankuznetsov/xbookmark.git
cd xbookmark
bundle install
bin/xbookmark --version
```

### Ubuntu / Debian

```bash
sudo apt install ruby ruby-dev build-essential libsqlite3-dev ffmpeg git

# Ubuntu < 24.04 and Debian 12 ship a Ruby older than 3.3.
# Install a modern Ruby with rbenv or mise if `ruby -v` reports < 3.3.

# whisper.cpp from source
git clone https://github.com/ggerganov/whisper.cpp.git && (cd whisper.cpp && make)

git clone https://github.com/ivankuznetsov/xbookmark.git
cd xbookmark
bundle install
bin/xbookmark --version
```

### Fedora

```bash
sudo dnf install ruby ruby-devel @development-tools sqlite-devel ffmpeg git

# whisper.cpp from source
git clone https://github.com/ggerganov/whisper.cpp.git && (cd whisper.cpp && make)

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

xbookmark reads a single `.env` file at the repo root. Copy the example and fill in the values:

```bash
cp .env.example .env
```

### Configuration file

```dotenv
# X API (OAuth 2.0 with PKCE)
X_CLIENT_ID=
X_CLIENT_SECRET=                                # optional; only needed for confidential-client app types
X_REDIRECT_URI=http://127.0.0.1:8765/callback   # loopback port 8765 is fixed; free it if already bound

# Where the markdown vault lives (leading ~ is expanded by xbookmark)
OBSIDIAN_VAULT_PATH=~/Vaults/xbookmark

# Whisper transcription
WHISPER_BACKEND=whisper.cpp   # or faster-whisper
WHISPER_MODEL=base.en

# codex CLI profile for enrichment
CODEX_PROFILE=default
```

### Set up X API access

1. Sign in at the [X developer portal](https://developer.x.com) and create a project, then create an app inside it.
2. Enable OAuth 2.0 on the app. Set the callback URL to `http://127.0.0.1:8765/callback` so it matches xbookmark's default loopback port.
3. Request the scopes `bookmark.read`, `users.read`, `tweet.read`, and `offline.access` (the last one is required so xbookmark can refresh access tokens without re-prompting).
4. Copy the Client ID into `X_CLIENT_ID`. `X_CLIENT_SECRET` is only required if your app type is a confidential client that issues a secret; PKCE public-client apps leave it blank.
5. Run `bin/xbookmark auth login`. The CLI opens your browser, completes the PKCE handshake, and stores tokens in `~/.config/xbookmark/credentials.json` (mode `0600`).

### What this will cost

xbookmark uses the official paid X API. See the [X developer portal product tiers](https://developer.x.com/en/portal/products) for the current Basic-tier monthly price and bookmark lookup quota. Use the published rate and quota on that page to estimate your own cost per 1000 bookmarks — pricing changes too often to quote a stable number here.

### codex authentication

Install the [`codex` CLI](https://github.com/openai/codex), run `codex login` once, point `CODEX_PROFILE` at the profile you want xbookmark to use, and confirm with `codex whoami`.

### Whisper backend

Set `WHISPER_BACKEND` to either `whisper.cpp` (default, fast on CPU, one-time C++ build) or `faster-whisper` (Python, GPU-friendly) and ensure the matching backend is on your `PATH` — see [Prerequisites](#prerequisites).

### Obsidian vault path

Set `OBSIDIAN_VAULT_PATH` to a directory you want to use as your vault. On first run xbookmark creates the directory if it is missing, including any missing parent directories, with mode `0700` (owner-only access). If the path already exists but is not a directory, xbookmark exits non-zero without modifying it. See [Obsidian integration](#obsidian-integration) for how to open it in Obsidian.

## Usage

### auth

Manage X API credentials.

```bash
bin/xbookmark auth login     # browser PKCE flow, stores tokens locally
bin/xbookmark auth logout    # delete stored tokens
bin/xbookmark auth status    # show the current account and token expiry
```

Example output:

```
Signed in as @ikuznetsov (id 1234567890). Access token expires in 1h 58m.
```

When the access token has already lapsed, `auth status` reports it as expired and silently refreshes it using the stored refresh token before printing the new expiry. If the refresh token itself has been revoked or has expired, `auth status` exits non-zero and prompts you to re-run `auth login`.

### backfill

Pull historical bookmarks into the vault.

```bash
bin/xbookmark backfill [--limit N] [--since YYYY-MM-DD] [--dry-run]
```

`--since` accepts an ISO-8601 calendar date (`YYYY-MM-DD`), interpreted in local time.

Example:

```bash
bin/xbookmark backfill --limit 100
```

Example output:

```
Fetched 100 bookmarks. Wrote 100 markdown files to ~/Vaults/xbookmark/bookmarks/.
```

### find

Full-text search across the vault.

```bash
bin/xbookmark find '<query>' [--limit N] [--json]
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

`find` searches the entire vault, so matches can span multiple month partitions in a single result set.

### enrich

Run the LLM enrichment pass.

```bash
bin/xbookmark enrich [--bookmark ID | --all] [--force]
```

Provide exactly one of `--bookmark` (a single tweet ID) or `--all` (every bookmark in the vault) — the two are mutually exclusive. `--force` re-runs enrichment on bookmarks that already have `enriched_at` set; without it, those bookmarks are skipped.

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
bin/xbookmark schedule install --daily [--at HH:MM]
bin/xbookmark schedule uninstall
bin/xbookmark schedule status
```

`--at` defaults to `09:00` local time.

Example output:

```
Daily ingest installed (systemd user timer `xbookmark-daily.timer`). Next run: tomorrow at 09:00.
```

See [Scheduling](#scheduling) for the per-OS artifact and log locations.

### Help

Every subcommand accepts `--help`. The top-level `bin/xbookmark --help` lists all subcommands and global flags.

## How it works

xbookmark talks to the X API v2 to fetch your bookmarks, writes each one as a markdown file with YAML frontmatter into your vault, then runs an enrichment pass (LLM summaries and tags via the default `codex` driver) and, for any linked audio or video, a local Whisper transcription. A QMD index over the vault gives you fast full-text search through `bin/xbookmark find`.

```text
   X API v2  -->  Ingest  -->  Enrich (codex)  -->  Markdown vault  -->  QMD index
                     |                ^                                      |
                     +-->  Whisper ---+                                      v
                          (linked media)                              bin/xbookmark find
```

## Obsidian integration

To open your vault in Obsidian, choose "Open folder as vault" from the Obsidian launcher and pick the directory you configured as `OBSIDIAN_VAULT_PATH`. Bookmarks land under `bookmarks/YYYY/MM/<id>.md`, partitioned by `bookmarked_at`.

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
bin/xbookmark schedule status
bin/xbookmark schedule uninstall
```

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
Switch to a smaller model (try `WHISPER_MODEL=tiny.en` first), or switch backend to `faster-whisper` and run it on a GPU. The [whisper.cpp build docs](https://github.com/ggerganov/whisper.cpp#quick-start) cover Metal, CUDA, and OpenBLAS acceleration.

**codex auth expired.**
Run `codex login` again, then re-run `bin/xbookmark enrich --all` — bookmarks left without `enriched_at` will be retried on the next pass.

**X API rate-limited me.**
`backfill` respects the published `bookmark.read` rate limits but a long backfill can still hit the current rate-limit window. Lower `--limit` and re-run later, or schedule a daily ingest instead. The X API [rate-limit reference](https://docs.x.com/x-api/fundamentals/rate-limits) on `docs.x.com` lists the current numbers.

**Where are my markdown files?**
Under `$OBSIDIAN_VAULT_PATH/bookmarks/YYYY/MM/<id>.md`. The `bin/xbookmark find` output prints these paths so you can open them in your editor directly, or `cd "$(dirname …)"` into the containing folder.

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

Pull requests should be small and focused — one logical change per PR — and pass `bundle exec rake test` plus the configured linters before pushing. Link any related issue in the PR description.

## Credits

xbookmark stands on the shoulders of:

- [codex](https://github.com/openai/codex) — today's default enrichment driver
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper)
- QMD — the local markdown full-text search engine that powers `bin/xbookmark find`
- [Obsidian](https://obsidian.md)
- The X API team

Without them this would be a much larger project.

## Security

Please report security issues privately to <ike@rabata.io> rather than opening a public GitHub issue. I aim to acknowledge reports within 3 business days and coordinate a fix and disclosure timeline from there.

## License

MIT, Copyright (c) 2026 Ivan Kuznetsov. See [LICENSE](LICENSE) for the full text.
