# xbookmark release pipeline

This file documents the moving parts of `.github/workflows/release.yml`.
Tag pushes (`vX.Y.Z`) drive the entire pipeline.

## Phase 1 — Build

| Job            | Runner                                    | Output                                              |
|----------------|-------------------------------------------|-----------------------------------------------------|
| `build-linux`  | `ghcr.io/tamatebako/tebako-ubuntu-20.04`  | `xbookmark-x86_64-linux` + `.sha256`                |
| `build-macos`  | `macos-14` + Homebrew prereqs + `tebako` gem | `xbookmark-arm64-darwin` + `.sha256`             |
| `build-deb`    | `ubuntu-latest` + FPM                     | `xbookmark_<ver>_amd64.deb`                         |
| `draft-release`| `ubuntu-latest`                            | Public prerelease with `SHA256SUMS`                |

## Phase 2 — Smoke gate

These four jobs each install xbookmark via one channel, then run
`xbookmark version`, `xbookmark doctor`, and `xbookmark uninstall
--purge --yes`.  All four must exit 0 before `promote-latest` runs.

| Job          | Channel               |
|--------------|-----------------------|
| `smoke-curl` | `install.sh`          |
| `smoke-brew` | Local Homebrew formula |
| `smoke-aur`  | AUR PKGBUILD          |
| `smoke-deb`  | `.deb` via `apt`      |

The prerelease is public before smoke tests run so URL-based installers can
download the exact candidate assets. `promote-latest` only runs after every
smoke gate exits successfully.

## Phase 3 — Promote + publish

| Job              | Trigger condition           | Effect                                              |
|------------------|-----------------------------|-----------------------------------------------------|
| `promote-latest` | all four smoke gates pass   | `gh release edit --prerelease=false --latest`       |
| `update-tap`     | `promote-latest` succeeded  | renders + pushes `Formula/xbookmark.rb` to the tap  |
| `update-aur`     | `promote-latest` succeeded  | renders + publishes the PKGBUILD via SSH to AUR    |

`update-tap` and `update-aur` are optional publisher jobs. They skip with
a notice when `HOMEBREW_TAP_DEPLOY_KEY` or `AUR_SSH_PRIVATE_KEY` is not
configured, so the GitHub release can still go green after the release
assets and install-channel smoke tests pass.

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
