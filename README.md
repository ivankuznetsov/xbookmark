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

## Installation

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
