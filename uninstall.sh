#!/bin/sh
# xbookmark uninstaller — POSIX sh sibling to install.sh.
#
# Usage:
#   curl -fsSL https://github.com/asterio/xbookmark/raw/main/uninstall.sh | sh
#
# Behavior:
#   1. If `xbookmark` is on PATH, run `xbookmark uninstall --purge --yes`
#      so the scheduler unit, libsecret entries, and config dir come down.
#   2. Then remove the binary at $XBOOKMARK_PREFIX/bin/xbookmark.
#
# Honors the same XBOOKMARK_PREFIX env var as install.sh (default
# $HOME/.local).

set -eu

XBOOKMARK_PREFIX="${XBOOKMARK_PREFIX:-$HOME/.local}"

say()  { printf '%s\n' "[xbookmark] $*"; }
warn() { printf '%s\n' "[xbookmark] $*" >&2; }

if command -v xbookmark >/dev/null 2>&1; then
  say "running xbookmark uninstall --purge --yes…"
  if ! xbookmark uninstall --purge --yes; then
    warn "xbookmark uninstall failed; proceeding to binary removal anyway."
  fi
else
  say "xbookmark not on PATH; skipping state cleanup."
fi

target="${XBOOKMARK_PREFIX}/bin/xbookmark"
if [ -e "$target" ]; then
  rm -f "$target"
  say "removed $target"
fi

say "uninstall complete."
