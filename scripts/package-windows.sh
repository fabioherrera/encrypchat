#!/usr/bin/env bash
# Windows packaging from a Linux host.
#
# The Flutter Windows runner is an MSVC project: this machine cannot produce
# encrypchat.exe. What it *can* do is wrap a bundle that CI (or a Windows
# desk) already built, using NSIS, into a per-user setup.exe — the analog of
# the Fedora RPM sitting next to the Linux tarball.
#
#   make package-windows
#   # or: scripts/package-windows.sh [bundle.zip|bundle-dir]
#
# Order: reuse a zip already in dist/, else download the latest successful
# windows.yml artifact, else explain how to start that workflow. Then compile
# packaging/windows/encrypchat.nsi with makensis.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Not common.sh: wrapping a zip does not need the Flutter SDK this host uses
# for Linux/Android.
VERSION="$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' "${ROOT}/apps/client/pubspec.yaml" | head -1)"
if [[ -z "${VERSION}" ]]; then
  echo "error: no version line in apps/client/pubspec.yaml" >&2
  exit 1
fi
ZIP="${ROOT}/dist/encrypchat-windows-x64-${VERSION}.zip"
SETUP="${ROOT}/dist/encrypchat-windows-x64-${VERSION}-setup.exe"
ARTIFACT="encrypchat-windows-x64-${VERSION}"
INPUT="${1:-}"

download_ci_zip() {
  if ! command -v gh >/dev/null 2>&1; then
    return 1
  fi
  local run="${ENCRYPCHAT_WINDOWS_RUN:-}"
  if [[ -z "${run}" ]]; then
    # Never pick a PR build: those share a version number with main and a
    # trojanized zip would become "the" Windows package. Pin with
    # ENCRYPCHAT_WINDOWS_RUN when you really want a specific run (this PR).
    echo "==> Looking for a successful windows.yml run on main"
    run="$(gh run list --workflow=windows.yml --status=success --branch main --limit 20 \
      --json databaseId,event --jq '[.[] | select(.event != "pull_request")][0].databaseId' 2>/dev/null || true)"
  else
    echo "==> Using ENCRYPCHAT_WINDOWS_RUN=${run}"
  fi
  if [[ -z "${run}" || "${run}" == "null" ]]; then
    return 1
  fi
  echo "==> Downloading artifact from run ${run}"
  local tmp
  tmp="$(mktemp -d "${ROOT}/dist/.gh-windows.XXXXXX")"
  # PR runs upload a -prN name; main/tags upload the plain version name.
  if ! gh run download "${run}" --dir "${tmp}" 2>/dev/null; then
    rm -rf "${tmp}"
    return 1
  fi
  local found
  found="$(find "${tmp}" -name 'encrypchat-windows-x64-*.zip' -type f | head -1)"
  if [[ -z "${found}" ]]; then
    rm -rf "${tmp}"
    return 1
  fi
  mkdir -p "${ROOT}/dist"
  mv -f "${found}" "${ZIP}"
  rm -rf "${tmp}"
  echo "  ${ZIP}"
  return 0
}

if [[ -n "${INPUT}" ]]; then
  :
elif [[ -f "${ZIP}" ]]; then
  INPUT="${ZIP}"
  echo "==> Reusing ${ZIP}"
elif download_ci_zip; then
  INPUT="${ZIP}"
else
  cat <<EOF
Encrypchat — Windows packaging (this host cannot compile the .exe)

The Flutter Windows runner is an MSVC project. This machine produces the
installer (setup.exe) once a bundle exists; it never produces encrypchat.exe.

Get the bundle, then re-run this script:

1. CI — .github/workflows/windows.yml on windows-latest. The repo is public,
   so the runner is not billed. workflow_dispatch needs a token with
   actions:write; a push that touches the workflow or packaging/windows, or
   a v* tag, also starts it.

     gh workflow run windows.yml          # from a token that can dispatch
     gh run watch --exit-status
     ENCRYPCHAT_WINDOWS_RUN=<id> scripts/package-windows.sh
     # make package-windows on its own only accepts a main/tag artifact,
     # never the last PR build (same version number, different bits).

2. On a Windows machine — free, and it is the machine that will test the
   build anyway:

     powershell -ExecutionPolicy Bypass -File scripts\\package-windows.ps1

   Needs: Rust (rustup), Flutter on PATH, Visual Studio with "Desktop
   development with C++", Developer Mode (Flutter links plugins with
   symlinks), and optionally NSIS (choco install nsis) so that script also
   writes the setup.exe. To move the source without a push:
   git bundle create encrypchat.bundle main

Either way the files are unsigned: SmartScreen will warn, and the way past
it is "More info" → "Run anyway".

The installer is per-user (%LOCALAPPDATA%\\Programs\\Encrypchat), no admin.
Uninstall leaves chats and the Credential Manager identity; "borrar
identidad" inside the app is what removes those.

See docs/phase-8.md. No public download URL exists yet — do not invent one.
EOF
  exit 2
fi

exec "${ROOT}/scripts/package-windows-installer.sh" "${INPUT}"
