# xbookmark

Sync your X (Twitter) bookmarks into a local markdown vault that doubles
as an Obsidian vault and a [QMD](https://github.com/) search collection.
Bookmarks land as per-tweet `.md` files with LLM-enriched frontmatter
(tags, topics, entities), media downloaded locally, and audio/video
transcribed with whisper.

Per-bookmark writes are transactional: a bookmark is either fully
written (markdown + media + enrichment) or not on disk at all.

Linux is the primary target (systemd `--user` timer); macOS is supported
via launchd.

## Install (Linux)

```bash
# Arch / Manjaro
pacman -S whisper.cpp ruby
# AUR — codex CLI and qmd
yay -S codex qmd

git clone https://github.com/asterio/xbookmark.git
cd xbookmark
bundle install
bundle binstubs --all
```

## Install (macOS)

```bash
brew install whisper-cpp ruby
brew install codex qmd  # or whatever upstream taps publish
git clone https://github.com/asterio/xbookmark.git
cd xbookmark
bundle install
bundle binstubs --all
```

## Configure

```bash
cp .env.example .env
# Fill X_CLIENT_ID and X_USER_ID at minimum.
# Defaults respect XDG dirs on Linux, Library/Application Support on macOS.
```

Required env keys:
- `X_CLIENT_ID` — your X app's OAuth 2.0 client id.
- `X_USER_ID` — the numeric X user whose bookmarks we read.

Tokens (`X_ACCESS_TOKEN`, `X_REFRESH_TOKEN`, `X_TOKEN_EXPIRES_AT`) are
populated automatically by `xbookmark auth login`.

## Run

```bash
# 1. Authenticate (once). Opens your browser.
bin/xbookmark auth login

# 2. Test backfill — pulls the most recent 100 bookmarks.
bin/xbookmark backfill --limit 100

# 3. Full backfill — all of them.
bin/xbookmark backfill

# 4. Search.
bin/xbookmark find 'tweet about ozempic'

# 5. Daily incremental sync — install scheduler.
bin/xbookmark install              # writes systemd timer / launchd plist
bin/xbookmark install --dry-run    # see what it would write
bin/xbookmark install --uninstall  # remove

# Useful diagnostics:
bin/xbookmark doctor               # checks codex/whisper/qmd/X auth
bin/xbookmark resync <tweet_id>    # force re-enrichment of one bookmark
```

### Linux: `loginctl enable-linger`

The systemd `--user` timer only fires while you are logged in. To run
even when no session is active:

```bash
loginctl enable-linger $USER
```

`xbookmark install` reminds you when linger is off.

## Vault layout

```
<vault>/
├── bookmarks/<YYYY>/<MM>/<DD>/<id>.md   # one note per bookmark
├── authors/<handle>.md
├── topics/<slug>.md
├── entities/<slug>.md
├── threads/<conversation_id>.md
├── links/<slug>.md
├── media/<tweet_id>/...                 # photos, mp4 video
└── .xbookmark/                          # state.db, scratch — Obsidian skips dotfolders
```

Bookmark notes wikilink into `authors/`, `topics/`, `entities/`, and
`threads/` pages. Aux pages do **not** maintain a list of bookmarks —
Obsidian's *Backlinks* panel is the source of truth.

## Failure handling

Bookmarks that fail any step (codex/whisper/X API/media download) get
recorded in `state.db` as `needs_retry` and are retried first on the
next run. After three attempts the row flips to `permanent_error`. Each
run prints a summary like:

```
synced 8, failed 2, retrying next run, elapsed 24.7s, api pages 1
```

## Develop

```bash
bundle exec rspec
```

Integration test (`spec/integration/v1_acceptance_spec.rb`) exercises
the entire pipeline against fixtures with no network access.

## License

MIT
