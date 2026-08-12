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

| File | Platform | Size (1.0.0) | Notes |
| --- | --- | --- | --- |
| `encrypchat-linux-x64-<version>.tar.gz` | Linux x64 | ~20 MB | Portable Flutter bundle + `install.sh`; libs stripped |
| `encrypchat-android-arm64-<version>.apk` | Android arm64 | ~16 MB | Release APK, arm64-v8a only; **debug-signed** unless `android/key.properties` exists — not for Play Store |

`<version>` comes from `apps/client/pubspec.yaml` (e.g. `1.0.0`).

The APK ships a single ABI on purpose: `crates/core` is cross-compiled for
aarch64 only, so any other ABI would install an app that dies loading the FFI
core. Native libs are compressed inside the APK (~16 MB download, ~35 MB on
device after install). See [docs/phase-8.md](../docs/phase-8.md) for the full
size breakdown and release-signing procedure.

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

- **iOS** — needs macOS + Xcode + signing, and `crates/core` linked into Runner
  (`-force_load libencrypchat_core.a`). Exact steps: `scripts/package-ios.sh`.
- **Windows** — needs a Windows host + VS 2022; no fake `.exe` here. Exact steps:
  `scripts/package-windows.sh`. The `.dll` install rule is already in
  `windows/CMakeLists.txt`.
- **Android release signing** — debug keystore today; drop
  `apps/client/android/key.properties` to sign for real (see docs/phase-8.md).
  Changing the signing key forces an uninstall, which wipes the local encrypted
  database.
