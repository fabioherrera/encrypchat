#!/usr/bin/env bash
# Windows packaging: not possible on this host, and no longer a dead end.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' "${ROOT}/apps/client/pubspec.yaml" | head -1)"

cat <<EOF
Encrypchat — Windows packaging (not built on this host)

The Flutter Windows runner is an MSVC project, so it cannot be cross-compiled
from Linux. This host produces no .exe / .zip, and never will.

Get a build from CI instead — .github/workflows/windows.yml runs the steps
below on a hosted Windows runner:

  gh workflow run windows.yml          # or the Actions tab → windows → Run workflow
  gh run download --name encrypchat-windows-x64-${VERSION}

The zip is kept for 30 days. It is unsigned: SmartScreen will warn, and the way
past it is "More info" → "Run anyway".

What is already wired for Windows (no host needed to verify):
  - windows/flutter/generated_plugin_registrant.cc registers flutter_webrtc,
    flutter_secure_storage_windows and file_selector_windows
  - windows/CMakeLists.txt installs apps/client/native/encrypchat_core.dll next
    to encrypchat.exe (native_library.dart looks there first)
  - image_picker has no Windows implementation: photo attach falls back to
    file_selector (same as Linux)

On a Windows host of your own (PowerShell, repo root):

  rustup target add x86_64-pc-windows-msvc
  cargo build -p encrypchat_core --release --target x86_64-pc-windows-msvc
  mkdir -Force apps\\client\\native
  copy target\\x86_64-pc-windows-msvc\\release\\encrypchat_core.dll apps\\client\\native\\

  cd apps\\client
  flutter config --enable-windows-desktop
  flutter pub get
  flutter build windows --release --tree-shake-icons

  # Bundle (contains encrypchat.exe, data\\, *.dll incl. encrypchat_core.dll):
  #   apps\\client\\build\\windows\\x64\\runner\\Release\\
  Compress-Archive -Path build\\windows\\x64\\runner\\Release\\* \`
    -DestinationPath ..\\..\\dist\\encrypchat-windows-x64-${VERSION}.zip

Verify before shipping: encrypchat_core.dll sits next to encrypchat.exe, and the
app reaches the identity screen (FFI loaded) instead of the core-missing banner.
CI checks exactly that before it uploads.

See docs/phase-8.md. No public download URL exists yet — do not invent one.
EOF
exit 2
