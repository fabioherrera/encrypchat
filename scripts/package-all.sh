#!/usr/bin/env bash
# Build every package this host can produce into dist/. Windows comes from CI
# (.github/workflows/windows.yml); iOS needs macOS. Both print notes and exit 2.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="${ROOT}/scripts"

echo "=== package-linux ==="
"${SCRIPTS}/package-linux.sh"
echo
echo "=== package-rpm ==="
"${SCRIPTS}/package-rpm.sh"
echo
echo "=== package-android ==="
"${SCRIPTS}/package-android.sh"
echo
echo "=== Artifacts ==="
ls -lh "${ROOT}/dist/"*.tar.gz "${ROOT}/dist/"*.rpm "${ROOT}/dist/"*.apk 2>/dev/null || true
echo
echo "Windows: make package-windows  (wraps a CI zip in the NSIS setup.exe;"
echo "         scripts/package-windows.sh explains how to get the zip)"
echo "iOS: needs a macOS host — scripts/package-ios.sh"
