#!/usr/bin/env bash
# Shared helpers for Encrypchat packaging scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="${ROOT}/.tools"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${ROOT}/target}"
export PATH="${TOOLS}/bin:${TOOLS}/flutter/bin:${PATH}"
export PUB_CACHE="${PUB_CACHE:-${TOOLS}/pub-cache}"
export PKG_CONFIG_PATH="${TOOLS}/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
FLUTTER_HOME="${FLUTTER_HOME:-${TOOLS}/home}"
mkdir -p "${PUB_CACHE}" "${FLUTTER_HOME}" "${ROOT}/dist"

if [[ -x "${TOOLS}/flutter/bin/flutter" ]]; then
  FLUTTER="${TOOLS}/flutter/bin/flutter"
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER="$(command -v flutter)"
else
  echo "error: flutter not found (expected ${TOOLS}/flutter or PATH)" >&2
  exit 1
fi

# pubspec "1.0.0+1" → "1.0.0"; fallback packaging tag if missing
encrypchat_version() {
  local v
  v="$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' "${ROOT}/apps/client/pubspec.yaml" | head -1)"
  if [[ -z "${v}" ]]; then
    v="0.1.0-f8"
  fi
  printf '%s' "${v}"
}

run_flutter() {
  HOME="${FLUTTER_HOME}" PUB_CACHE="${PUB_CACHE}" "${FLUTTER}" "$@"
}
