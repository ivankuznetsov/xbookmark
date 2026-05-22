---
title: Active Areas
type: active-areas
source: git log --name-only; git status; README.md; lib/xbookmark/config.rb; lib/xbookmark/cli.rb
created: 2026-05-14
updated: 2026-05-22
tags: [activity]
---

**TLDR**: Current work is focused on making new xbookmark setups follow the implemented CLI and on separating the runtime bookmark wiki from this repository's project LLM wiki.

## Active PR

Branch `fix/wiki-path-config` updates the public setup contract and runtime terminology:

- Preferred runtime output path is `XBOOKMARK_WIKI_PATH`.
- The runtime bookmark wiki is standalone and can be opened from Obsidian later.
- The repository `wiki/` remains the project LLM wiki and is not the runtime output directory.
- `--wiki` is the preferred CLI override; `--vault`, `XBOOKMARK_VAULT`, and `OBSIDIAN_VAULT_PATH` remain compatibility aliases.
- New defaults use `xbookmark-wiki`; no migration from the previous local `xbookmark-vault` name is needed before release.

## Setup Reliability

The README now describes only implemented setup commands:

- `bin/xbookmark auth login`
- `bin/xbookmark auth status`
- `bin/xbookmark backfill [--limit N]`
- `bin/xbookmark sync`
- `bin/xbookmark find QUERY [--limit N]`
- `bin/xbookmark install [--time HH:MM] [--dry-run] [--uninstall]`

Deferred command shapes such as `schedule`, `auth refresh/logout`, `enrich`, `--config`, `backfill --since`, and `find --json` should stay out of setup docs until implemented.

Related: [[architecture]], [[commands]], [[api]], [[dependencies]], [[gaps]].
