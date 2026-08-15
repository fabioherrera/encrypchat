#!/usr/bin/env bash
# Wrap a Flutter Windows release bundle in an NSIS per-user installer.
#
# The .exe inside the bundle is an MSVC binary: this script does not compile
# it. It takes a folder (or a zip of that folder) that already contains
# encrypchat.exe + encrypchat_core.dll and writes
# dist/encrypchat-windows-x64-<version>-setup.exe.
#
#   scripts/package-windows-installer.sh [bundle-dir|bundle.zip]
#
# With no argument it looks for dist/encrypchat-windows-x64-<version>.zip.
# makensis runs on Linux (this host) and on Windows; the stub is 32-bit and
# that is normal — it still installs the 64-bit app.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Not common.sh: that file requires a Flutter SDK, and wrapping a zip on Linux
# does not compile anything.
VERSION="$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' "${ROOT}/apps/client/pubspec.yaml" | head -1)"
if [[ -z "${VERSION}" ]]; then
  echo "error: no version line in apps/client/pubspec.yaml" >&2
  exit 1
fi
OUT="${ROOT}/dist/encrypchat-windows-x64-${VERSION}-setup.exe"
NSI="${ROOT}/packaging/windows/encrypchat.nsi"
ICON="${ROOT}/apps/client/windows/runner/resources/app_icon.ico"
LICENSE="${ROOT}/LICENSE"
INPUT="${1:-${ROOT}/dist/encrypchat-windows-x64-${VERSION}.zip}"

find_makensis() {
  if command -v makensis >/dev/null 2>&1; then
    command -v makensis
    return 0
  fi
  local candidate
  for candidate in \
    "/c/Program Files (x86)/NSIS/makensis.exe" \
    "/c/Program Files/NSIS/makensis.exe" \
    "C:/Program Files (x86)/NSIS/makensis.exe" \
    "C:/Program Files/NSIS/makensis.exe"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  echo "error: makensis not found. On this host: sudo apt-get install nsis" >&2
  echo "On Windows: choco install nsis  (or the NSIS installer from nsis.sourceforge.io)" >&2
  exit 1
}

if [[ ! -f "${NSI}" ]]; then
  echo "error: missing ${NSI}" >&2
  exit 1
fi
if [[ ! -f "${ICON}" ]]; then
  echo "error: missing ${ICON}" >&2
  exit 1
fi
if [[ ! -f "${LICENSE}" ]]; then
  echo "error: missing ${LICENSE}" >&2
  exit 1
fi
if [[ ! -e "${INPUT}" ]]; then
  echo "error: no Windows bundle at ${INPUT}" >&2
  echo "Build it on Windows (scripts\\package-windows.ps1) or download the CI zip, then re-run." >&2
  exit 1
fi

MAKENSIS="$(find_makensis)"
STAGE="${ROOT}/dist/.stage-windows-installer"
rm -rf "${STAGE}"
mkdir -p "${STAGE}"

if [[ -d "${INPUT}" ]]; then
  echo "==> Bundle directory ${INPUT}"
  BUNDLE="${INPUT}"
elif [[ -f "${INPUT}" ]]; then
  echo "==> Unzip ${INPUT}"
  python3 - "${INPUT}" "${STAGE}/bundle" <<'PY'
import sys, zipfile
from pathlib import Path
src, dest = Path(sys.argv[1]), Path(sys.argv[2])
dest.mkdir(parents=True)
with zipfile.ZipFile(src) as zf:
    zf.extractall(dest)
# A zip of the Release folder has exe at the root. A zip of a named folder
# has one extra level; flatten that so NSIS always sees the same layout.
entries = [p for p in dest.iterdir()]
if len(entries) == 1 and entries[0].is_dir() and not (dest / "encrypchat.exe").exists():
    inner = entries[0]
    for child in inner.iterdir():
        child.rename(dest / child.name)
    inner.rmdir()
PY
  BUNDLE="${STAGE}/bundle"
else
  echo "error: ${INPUT} is neither a directory nor a zip" >&2
  exit 1
fi

for needed in encrypchat.exe encrypchat_core.dll; do
  if [[ ! -f "${BUNDLE}/${needed}" ]]; then
    echo "error: the bundle is incomplete: missing ${needed} in ${BUNDLE}" >&2
    exit 1
  fi
done
if [[ ! -d "${BUNDLE}/data" ]]; then
  echo "error: the bundle is incomplete: missing data/ in ${BUNDLE}" >&2
  exit 1
fi

# NSIS File /r wants native separators. On Windows Git Bash that is backslash;
# on Linux the POSIX makensis accepts either, and we pass the real path.
BUNDLE_NATIVE="${BUNDLE}"
if command -v cygpath >/dev/null 2>&1; then
  BUNDLE_NATIVE="$(cygpath -w "${BUNDLE}")"
  OUT_NATIVE="$(cygpath -w "${OUT}")"
  ICON_NATIVE="$(cygpath -w "${ICON}")"
  LICENSE_NATIVE="$(cygpath -w "${LICENSE}")"
  NSI_NATIVE="$(cygpath -w "${NSI}")"
else
  OUT_NATIVE="${OUT}"
  ICON_NATIVE="${ICON}"
  LICENSE_NATIVE="${LICENSE}"
  NSI_NATIVE="${NSI}"
fi

echo "==> NSIS ${VERSION}"
mkdir -p "$(dirname "${OUT}")"
rm -f "${OUT}"
"${MAKENSIS}" \
  -DPRODUCT_VERSION="${VERSION}" \
  -DBUNDLE_DIR="${BUNDLE_NATIVE}" \
  -DOUT_FILE="${OUT_NATIVE}" \
  -DICON_FILE="${ICON_NATIVE}" \
  -DLICENSE_FILE="${LICENSE_NATIVE}" \
  "${NSI_NATIVE}"

rm -rf "${STAGE}"

if [[ ! -f "${OUT}" ]]; then
  echo "error: makensis reported success but ${OUT} is missing" >&2
  exit 1
fi

# The stub is a 32-bit PE even when the payload is x64. file(1) saying
# "Intel 80386" is expected and not a packaging slip.
if command -v file >/dev/null 2>&1; then
  file "${OUT}"
fi

bytes="$(wc -c < "${OUT}" | tr -d ' ')"
if [[ "${bytes}" -lt 1000000 ]]; then
  rm -f "${OUT}"
  echo "error: installer was ${bytes} bytes — too small to hold the Flutter bundle" >&2
  exit 1
fi

mib="$(python3 -c "print(f'{int(${bytes})/1048576:.1f}')")"
echo "OK: ${OUT} (${mib} MiB)"
echo "Per-user, unsigned. SmartScreen: More info → Run anyway."
echo "Installs to %LOCALAPPDATA%\\Programs\\Encrypchat. Uninstall leaves chats and the credential-store identity."
