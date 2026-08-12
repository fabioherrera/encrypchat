#!/usr/bin/env bash
# Windows packaging stub (Phase 8 gap — no Windows host on this builder).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cat <<EOF
Encrypchat — Windows packaging (not built on this host)

Gap: producing a Windows installer requires a Windows (or cross-MSVC) toolchain
and Flutter Windows desktop build. This Linux CI/dev host does not ship fake
.binaries.

When a Windows host is available:

  cd ${ROOT}
  make build-ffi   # produces .dll via appropriate target when wired
  cd apps/client && flutter build windows --release
  # Then MSIX / Inno / portable zip into dist/encrypchat-windows-x64-<ver>.zip

See docs/phase-8.md for status. Artifact path (future): dist/
EOF
exit 2
