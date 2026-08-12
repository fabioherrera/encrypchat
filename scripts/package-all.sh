#!/usr/bin/env bash
# Build Linux + Android packages into dist/. Windows/iOS are stubs (exit 2).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="${ROOT}/scripts"

echo "=== package-linux ==="
"${SCRIPTS}/package-linux.sh"
echo
echo "=== package-android ==="
"${SCRIPTS}/package-android.sh"
echo
echo "=== Artifacts ==="
ls -lh "${ROOT}/dist/"*.tar.gz "${ROOT}/dist/"*.apk 2>/dev/null || true
echo
echo "Windows/iOS: run scripts/package-windows.sh or package-ios.sh for gap notes (exit 2)."
