#!/usr/bin/env bash
# iOS packaging stub (Phase 8 gap — requires macOS + Xcode + signing).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cat <<EOF
Encrypchat — iOS packaging (not built on this host)

Gap: IPA / TestFlight builds require macOS, Xcode, Apple Developer signing,
and an iOS NDK/FFI staticlib build of crates/core. This Linux host does not
produce placeholder IPAs.

When a Mac is available:

  cd ${ROOT}
  # Build ios target for encrypchat_core → Framework / jni-equivalent
  cd apps/client && flutter build ipa --release
  # Distribute via TestFlight or ad-hoc; document in dist/README.md

See docs/phase-8.md for status.
EOF
exit 2
