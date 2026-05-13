# xbookmark

Own your X bookmarks as a local, Obsidian-ready markdown vault with LLM enrichment and Whisper transcription.

xbookmark pulls your X (formerly Twitter) bookmarks through the official paid X API v2, writes each one to a plain markdown file with YAML frontmatter, runs an LLM enrichment pass for summaries and tags, and transcribes any linked audio or video locally with Whisper. It is built for people who keep notes in Obsidian or any markdown-first system and are tired of X bookmarks being unsearchable and ephemeral. Everything runs on your machine; nothing leaves it except the calls you authorise to the X API and your configured LLM provider.

<p align="center">
  <a href="https://github.com/ikuznetsov/xbookmark/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/ikuznetsov/xbookmark/ci.yml?branch=main" alt="Build status"></a>
  <a href="#"><img src="https://img.shields.io/badge/gem-unreleased-lightgrey" alt="Gem version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License"></a>
  <img src="https://img.shields.io/badge/ruby-%E2%89%A5%203.3-red" alt="Ruby version">
</p>

<p align="center">
  <img src="docs/assets/demo.gif" alt="xbookmark backfill and find demo">
</p>

```bash
git clone https://github.com/ikuznetsov/xbookmark.git
cd xbookmark
bundle install
bin/xbookmark auth login
bin/xbookmark backfill --limit 100
bin/xbookmark find 'rails'
```

## Features

- One-shot backfill of your entire X bookmark history into a local markdown vault.
- Daily incremental ingest via a built-in scheduler (systemd, launchd, or cron).
- Obsidian-friendly markdown output with YAML frontmatter and stable file naming.
- Full-text search over the vault via a local QMD index.
- LLM enrichment of each bookmark (summary, tags) through the `codex` CLI.
- Local Whisper transcription of audio and video linked from a bookmark.
- Official X API v2 only, via OAuth 2.0 with PKCE. No cookie scraping.
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
yay -S whisper.cpp-git   # or build whisper.cpp from source

git clone https://github.com/ikuznetsov/xbookmark.git
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

git clone https://github.com/ikuznetsov/xbookmark.git
cd xbookmark
bundle install
bin/xbookmark --version
```

### Fedora

```bash
sudo dnf install ruby ruby-devel @development-tools sqlite-devel ffmpeg git

# whisper.cpp from source
git clone https://github.com/ggerganov/whisper.cpp.git && (cd whisper.cpp && make)

git clone https://github.com/ikuznetsov/xbookmark.git
cd xbookmark
bundle install
bin/xbookmark --version
```

### macOS

```bash
brew install ruby ffmpeg sqlite git whisper-cpp

# If `ruby -v` still shows the system Ruby, prepend Homebrew's Ruby to PATH:
#   echo 'export PATH="$(brew --prefix ruby)/bin:$PATH"' >> ~/.zshrc

git clone https://github.com/ikuznetsov/xbookmark.git
cd xbookmark
bundle install
bin/xbookmark --version
```

A published gem is on the [Roadmap](#roadmap); until then, clone-and-bundle is the supported install path.

## Configuration

## Usage

## How it works

## Obsidian integration

## Scheduling

## FAQ

## Roadmap

## Contributing

## Credits

## Security

## License
