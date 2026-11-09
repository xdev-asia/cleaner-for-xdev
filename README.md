# Cleaner for xDev

A native macOS app that shows where your disk space goes and cleans it up safely, with developer machines in mind
(Xcode, Android, Docker, Node.js, Rust, Git worktrees).

- **Smart Scan:** one button scans your Home folder for caches and build outputs (Xcode, Gradle, node_modules, app
  caches), selects the *Safe* items, and cleans after you confirm. The App Store edition asks for the Home folder once
  and remembers it.
- **Overview:** used and free space per volume, the largest items, scan a disk, your Home folder or any folder.
- **Folders:** a treemap you can click to drill into, next to a table sorted by size.
- **Cleanable:** caches and build outputs grouped by tool, each marked *Safe* or *Review*. *Review* items are never
  selected by default.
- **Large Files:** filter by size, kind and age.
- **Duplicates:** same size, then the same first 64 KB, then the same SHA-256.

## Safety

- Files are moved to the Trash, never deleted, except for the explicit *Empty Trash* item.
- Tools clean their own caches where they can (`cargo clean`, `pnpm store prune`, `docker builder prune -af`,
  `xcrun simctl delete unavailable`, `git worktree remove`).
- Git worktrees with uncommitted changes are never cleaned.
- System locations (`/System`, `/usr`, `/bin`, `/sbin`, `/Library`, your Home folder itself, `~/Library` itself)
  are refused.
- Every clean-up goes through a confirmation sheet that lists each step.
- No network access, no analytics.

## Install

1. Download `CleanerForXDev-<version>.dmg` from [Releases](https://github.com/xdev-asia/cleaner-for-xdev/releases)
   and drag the app to Applications. Releases are signed with Developer ID and notarized by Apple.
2. To scan the whole disk, turn on the app in **System Settings › Privacy & Security › Full Disk Access**. Without
   it the app still scans what macOS allows and lists the folders it could not read.

Requires macOS 26 or later.

### Mac App Store edition

A sandboxed edition (target `CleanerAppStore`) scans only folders you choose, moves items to the Trash and never
runs other tools. `./scripts/appstore.sh` builds and signs its installer package; see the script for what it needs.
[Support](https://xdev-asia.github.io/cleaner-for-xdev/) ·
[Privacy policy](https://xdev-asia.github.io/cleaner-for-xdev/privacy/)

## Build from source

Requirements: Xcode 27 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
swift test                 # engine tests (CleanerKit)
./scripts/build-app.sh     # build/Cleaner for xDev.app and a DMG
```

`build-app.sh` signs ad-hoc unless a build keychain is set up (see `scripts/signing.sh`). macOS ties Full Disk
Access to the signature, so an ad-hoc build needs the permission granted again after each rebuild.

`./scripts/release.sh` builds a release: signed with Developer ID, notarized and stapled. It needs a Developer ID
Application certificate in the build keychain and a `notarytool` profile (`cleaner-notary`) stored there.

## Layout

```
Sources/CleanerKit   engine without UI: scanner, rules, large files, duplicates, cleaner, treemap
Tests                Swift Testing suites for the engine
App                  SwiftUI app
project.yml          XcodeGen project (the .xcodeproj is generated, not committed)
scripts              build, DMG, release, App Store and icon scripts
docs                 support and privacy pages (GitHub Pages), design docs
```

## License

[MIT](LICENSE)
