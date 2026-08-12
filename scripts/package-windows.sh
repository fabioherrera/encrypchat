#!/usr/bin/env bash
# Windows packaging (Phase 8 gap — needs a Windows host; no fake binaries here).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' "${ROOT}/apps/client/pubspec.yaml" | head -1)"

cat <<EOF
Encrypchat — Windows packaging (not built on this host)

Gap: needs Windows 10/11 + Visual Studio 2022 (Desktop C++ workload) + Flutter
Windows desktop. Cross-compiling the MSVC Flutter runner from Linux is not
supported, so this Linux host produces no .exe / .zip.

What is already wired for Windows (no host needed to verify):
  - windows/flutter/generated_plugin_registrant.cc registers flutter_webrtc,
    flutter_secure_storage_windows and file_selector_windows
  - windows/CMakeLists.txt installs apps/client/native/encrypchat_core.dll next
    to encrypchat.exe (native_library.dart looks there first)
  - image_picker has no Windows implementation: photo attach falls back to
    file_selector (same as Linux)

On a Windows host (PowerShell, repo root):

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

See docs/phase-8.md. No public download URL exists yet — do not invent one.
EOF
exit 2
