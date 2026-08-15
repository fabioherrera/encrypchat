# `dist/` — packaged Encrypchat installers

This directory holds **local / CI build artifacts**. Binaries are gitignored; only this README is tracked.

## Produce artifacts

From the monorepo root (toolchain: `.tools/bin`, Flutter in `.tools/flutter`, JDK optional in `.tools/jdk-21`):

```bash
make package          # Linux tarball + Fedora RPM + Android APK
# or:
make package-linux
make package-rpm
make package-android
```

Scripts: `scripts/package-linux.sh`, `scripts/package-rpm.sh`, `scripts/package-android.sh`, `scripts/package-windows.sh`, `scripts/package-all.sh`.  
Windows `.exe` is compiled on Windows (`scripts\package-windows.ps1`) or in CI (`.github/workflows/windows.yml`). This Linux host then wraps that bundle in an NSIS per-user installer: `make package-windows`. iOS still needs a macOS host (`scripts/package-ios.sh`, exit 2).

## Expected files (after a successful package)

| File | Platform | Size (1.0.6) | Notes |
| --- | --- | --- | --- |
| `encrypchat-linux-x64-<version>.tar.gz` | Linux x64 | ~22 MB | Portable Flutter bundle + `install.sh`; libs stripped |
| `encrypchat-<version>-1.fc*.x86_64.rpm` | Fedora x64 | ~19 MB | Same bundle under `/usr/lib64/encrypchat`; unsigned |
| `encrypchat-android-arm64-<version>.apk` | Android arm64 | ~22 MB | Release APK, arm64-v8a only; **debug-signed** unless `android/key.properties` exists — not for Play Store |
| `encrypchat-windows-x64-<version>.zip` | Windows x64 | ~25 MB | Portable Flutter bundle; built on a Windows host or by CI (`windows-latest`, 30 days) |
| `encrypchat-windows-x64-<version>-setup.exe` | Windows x64 | ~25 MB | NSIS per-user installer of that bundle (`make package-windows` on Linux, or the same `.ps1` when NSIS is installed) |

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

**Fedora** — preferable to the tarball on a machine used for testing: `dnf` takes
every file back out, so "reinstall from scratch" means what it says.

```bash
sudo dnf install ./encrypchat-<version>-1.fc*.x86_64.rpm
encrypchat
sudo dnf remove encrypchat   # leaves no install tree behind
```

Unsigned and with no repository behind it, so dnf will say so. Your data lives in
`~/.local/share/com.encrypchat.encrypchat` and survives the removal: that is the
encrypted database, and only the in-app identity delete removes it.

**Android**

```bash
adb install -r encrypchat-android-arm64-<version>.apk
```

**Windows** — two artifacts, same unsigned binary. The zip runs in place. The
`setup.exe` is per-user (no admin): Start Menu + `%LOCALAPPDATA%\Programs\Encrypchat`.
Uninstall leaves chats and the Credential Manager identity; use «borrar identidad»
inside the app to remove those.

On a Windows machine, from the repo root (writes both the zip and, if NSIS is
installed, the installer):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\package-windows.ps1
```

From this Linux host, once a bundle exists (CI artifact or a copied zip):

```bash
make package-windows
# → dist/encrypchat-windows-x64-<version>-setup.exe
```

`scripts/package-windows.sh` reuses `dist/*.zip`, or downloads the latest
successful `windows.yml` run. A PR that touches the Windows packaging starts
that workflow; `gh workflow run windows.yml` also does, from a token with
`actions:write`.

Unsigned, so SmartScreen blocks the first run: "More info" → "Run anyway".

## Distribution

Test builds go to **GitHub Releases** as prereleases, and the landing links
those files: https://encrypchat.com/es/download (and `/en/download`). Tag names
avoid the `v*` pattern on purpose — that one triggers `windows.yml`.

```bash
gh release download pruebas-2026-08-13-ui --dir .
sha256sum -c SHA256SUMS
```

Do not invent a CDN in front of this. When a new batch replaces the previous
one, bump `TEST_RELEASE_TAG` in `apps/web/src/lib/site.ts`.

## Gaps

- **iOS** — needs macOS + Xcode + signing, and `crates/core` linked into Runner
  (`-force_load libencrypchat_core.a`). Exact steps: `scripts/package-ios.sh`.
- **Windows** — no longer a gap in *producing* a binary: CI or a Windows host
  compiles the bundle; this Linux host wraps it in `*-setup.exe`. Nothing is
  signed and nobody has run it on real hardware yet.
- **Android release signing** — debug keystore today; drop
  `apps/client/android/key.properties` to sign for real (see docs/phase-8.md).
  Changing the signing key forces an uninstall, which wipes the local encrypted
  database.
