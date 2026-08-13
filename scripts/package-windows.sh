#!/usr/bin/env bash
# Windows packaging: not possible on this host, and no longer a dead end.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' "${ROOT}/apps/client/pubspec.yaml" | head -1)"

cat <<EOF
Encrypchat — Windows packaging (not built on this host)

The Flutter Windows runner is an MSVC project, so it cannot be cross-compiled
from Linux. This host produces no .exe / .zip, and never will.

Two ways to get one, both running the same steps:

1. On a Windows machine of your own — free, and it is the machine that will
   test the build anyway. Copy the repo over and run, from the repo root:

     powershell -ExecutionPolicy Bypass -File scripts\\package-windows.ps1

   It checks the toolchain first, builds the core and the client, verifies the
   bundle and writes dist\\encrypchat-windows-x64-${VERSION}.zip.
   Needs: Rust (rustup), Flutter on PATH, Visual Studio with "Desktop
   development with C++", and Developer Mode on (Flutter links plugins with
   symlinks). To move the source without a push:
   git bundle create encrypchat.bundle main  →  git clone encrypchat.bundle

2. From CI — .github/workflows/windows.yml runs it on a hosted runner:

     gh workflow run windows.yml          # or the Actions tab → windows → Run workflow
     gh run download --name encrypchat-windows-x64-${VERSION}

   The zip is kept for 30 days. Note the cost: on a private repo, Windows
   runners bill Actions minutes at 2x, so one build is roughly 30-50 minutes of
   the monthly allowance.

Either way the zip is unsigned: SmartScreen will warn, and the way past it is
"More info" → "Run anyway".

What is already wired for Windows (no host needed to verify):
  - windows/flutter/generated_plugin_registrant.cc registers flutter_webrtc,
    flutter_secure_storage_windows and file_selector_windows
  - windows/CMakeLists.txt installs apps/client/native/encrypchat_core.dll next
    to encrypchat.exe (native_library.dart looks there first)
  - image_picker has no Windows implementation: photo attach falls back to
    file_selector (same as Linux)

Verify before shipping: encrypchat_core.dll sits next to encrypchat.exe, and the
app reaches the identity screen (FFI loaded) instead of the core-missing banner.
Both paths check exactly that before they package.

See docs/phase-8.md. No public download URL exists yet — do not invent one.
EOF
exit 2
