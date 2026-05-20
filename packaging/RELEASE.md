# xbookmark release pipeline

This file documents the moving parts of `.github/workflows/release.yml`.
Tag pushes (`vX.Y.Z`) drive the entire pipeline.

## Phase 1 — Build

| Job            | Runner                                    | Output                                              |
|----------------|-------------------------------------------|-----------------------------------------------------|
| `build-linux`  | `ghcr.io/tamatebako/tebako-ubuntu-20.04`  | `xbookmark-x86_64-linux` + `.sha256`                |
| `build-macos`  | `macos-14` + Homebrew `tebako` formula    | `xbookmark-arm64-darwin` + `.sha256`                |
| `build-deb`    | `ubuntu-latest` + FPM                     | `xbookmark_<ver>_amd64.deb`                         |
| `draft-release`| `ubuntu-latest`                            | GitHub Release marked `draft`, with `SHA256SUMS`   |

## Phase 2 — Smoke gate

These four jobs each install xbookmark via one channel, then run
`xbookmark version`, `xbookmark doctor`, and `xbookmark uninstall
--purge --yes`.  All four must exit 0 before `promote-latest` runs.

| Job          | Channel               |
|--------------|-----------------------|
| `smoke-curl` | `install.sh`          |
| `smoke-brew` | Homebrew tap          |
| `smoke-aur`  | AUR PKGBUILD          |
| `smoke-deb`  | `.deb` via `apt`      |

`smoke-brew` is marked `continue-on-error: true` for the very first
release of v1 because the tap repo will not exist yet; once the tap is
bootstrapped this flag should be removed.

## Phase 3 — Promote + publish

| Job              | Trigger condition           | Effect                                              |
|------------------|-----------------------------|-----------------------------------------------------|
| `promote-latest` | all four smoke gates pass   | `gh release edit --draft=false --latest`            |
| `update-tap`     | `promote-latest` succeeded  | renders + pushes `Formula/xbookmark.rb` to the tap  |
| `update-aur`     | `promote-latest` succeeded  | renders + publishes the PKGBUILD via SSH to AUR    |

## Bootstrapping the tap repo

Before the first tag push:

1. Create `ivankuznetsov/homebrew-tap` on GitHub.
2. `git init` it locally with a minimal layout (`Formula/` + `README.md`).
3. Push a deploy key whose private half is stored as the
   `HOMEBREW_TAP_DEPLOY_KEY` secret on the xbookmark repo.

## Bootstrapping the AUR account

1. Create or claim the `xbookmark` AUR package name on aur.archlinux.org.
2. Register an SSH key whose private half is stored as the
   `AUR_SSH_PRIVATE_KEY` secret on the xbookmark repo.

## Manual smoke testing

To exercise a release candidate locally without pushing a tag, run:

```bash
./install.sh                          # downloads latest release
xbookmark version
xbookmark doctor
xbookmark uninstall --purge --yes
```
