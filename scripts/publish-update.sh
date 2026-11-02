#!/usr/bin/env bash
# Writes the signed update catalog for one release into apps/web/public.
#
#   scripts/publish-update.sh --base-url https://.../download/v1.1.0 \
#     --apk dist/x.apk --windows-setup dist/x-setup.exe --notes "..."
#
# Run it on the machine that holds the signing key. The key stays out of the repo:
# UPDATE_SIGNING_KEY defaults to ~/.encrypchat-release/update-signing.pem.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY="${UPDATE_SIGNING_KEY:-${HOME}/.encrypchat-release/update-signing.pem}"
VERSION="$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' "${ROOT}/apps/client/pubspec.yaml" | head -1)"
BASE_URL="" APK="" SETUP="" NOTES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --apk) APK="$2"; shift 2 ;;
    --windows-setup) SETUP="$2"; shift 2 ;;
    --notes) NOTES="$2"; shift 2 ;;
    *) echo "error: unknown argument $1" >&2; exit 1 ;;
  esac
done

[[ -n "${BASE_URL}" ]] || { echo "error: --base-url is required" >&2; exit 1; }
[[ "${BASE_URL}" == https://* ]] || { echo "error: --base-url must be https" >&2; exit 1; }
[[ -f "${KEY}" ]] || { echo "error: signing key not found at ${KEY}" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

python3 - "${VERSION}" "${BASE_URL%/}" "${NOTES}" "${APK}" "${SETUP}" > "${WORK}/payload.json" <<'PY'
import hashlib, json, os, sys
version, base, notes, apk, setup = sys.argv[1:6]
def entry(path):
    with open(path, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    name = os.path.basename(path)
    return {"url": f"{base}/{name}", "sha256": digest, "file": name}
packages = {}
if apk:
    packages["android-apk"] = entry(apk)
if setup:
    packages["windows-setup"] = entry(setup)
if not packages:
    sys.exit("error: pass --apk and/or --windows-setup")
json.dump({
    "version": version,
    "notes": notes,
    "download": "https://encrypchat.com/es/download",
    "packages": packages,
}, sys.stdout, ensure_ascii=False, indent=2)
PY

openssl pkeyutl -sign -rawin -inkey "${KEY}" -in "${WORK}/payload.json" -out "${WORK}/payload.sig"

python3 - "${WORK}/payload.json" "${WORK}/payload.sig" \
  > "${ROOT}/apps/web/public/update-manifest.json" <<'PY'
import base64, json, sys
payload = open(sys.argv[1], "rb").read()
signature = open(sys.argv[2], "rb").read()
json.dump({
    "payload": base64.b64encode(payload).decode(),
    "signature": base64.b64encode(signature).decode(),
}, sys.stdout, indent=2)
print()
PY

# Builds before 1.1.0 read this file and were signed with another key, so they
# cannot update in place. No package here: they are sent to the download page.
python3 - "${VERSION}" > "${ROOT}/apps/web/public/latest.json" <<'PY'
import json, sys
json.dump({
    "version": sys.argv[1],
    "notes": "Esta versión cambia la firma de la app. Hay que instalarla una vez desde la web.",
    "download": "https://encrypchat.com/es/download",
    "packages": {},
}, sys.stdout, ensure_ascii=False, indent=2)
print()
PY

echo "update-manifest.json written for ${VERSION}"
