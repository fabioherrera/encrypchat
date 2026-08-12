# `dist/` — packaged Encrypchat installers

This directory holds **local / CI build artifacts**. Binaries are gitignored; only this README is tracked.

## Produce artifacts

From the monorepo root (toolchain: `.tools/bin`, Flutter in `.tools/flutter`, JDK optional in `.tools/jdk-21`):

```bash
make package          # Linux tarball + Android APK
# or:
make package-linux
make package-android
```

Scripts: `scripts/package-linux.sh`, `scripts/package-android.sh`, `scripts/package-all.sh`.  
Windows / iOS stubs: `scripts/package-windows.sh`, `scripts/package-ios.sh` (document gaps; exit 2).

## Expected files (after a successful package)

| File | Platform | Notes |
| --- | --- | --- |
| `encrypchat-linux-x64-<version>.tar.gz` | Linux x64 | Portable Flutter bundle + `install.sh` |
| `encrypchat-android-arm64-<version>.apk` | Android arm64 | Release APK; **debug-signed** OK for sideload — not for Play Store |

`<version>` comes from `apps/client/pubspec.yaml` (e.g. `1.0.0`).

## Install

**Linux**

```bash
tar -xzf encrypchat-linux-x64-<version>.tar.gz
cd encrypchat-linux-x64-<version>
./install.sh
# → ~/.local/share/encrypchat, symlink ~/.local/bin/encrypchat, desktop entry
encrypchat
```

**Android**

```bash
adb install -r encrypchat-android-arm64-<version>.apk
```

## Distribution

Public download URLs will land on **GitHub Releases** when publishing starts. Until then, use local `dist/` or build from source — see [docs/phase-8.md](../docs/phase-8.md). Do not invent live CDN links that 404.

## Gaps

- **iOS** — needs macOS + Xcode + signing.
- **Windows** — needs a Windows host (or documented cross toolchain); no fake `.exe` here.
- **F5–F7** (relay, media, WebRTC) deferred relative to packaging-first testing.
