#!/usr/bin/env bash
# Build the Fedora package → dist/encrypchat-<version>-1.fc*.x86_64.rpm
#
# Why an RPM when there is already a tarball: the tarball installs into the user prefix and
# leaves nothing for the system to track. On a machine used for testing, `dnf remove` taking
# every file back out is worth more than portability — and it is the only way to be sure a
# reinstall is really a fresh one.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if ! command -v rpmbuild >/dev/null 2>&1; then
  echo "error: rpmbuild not found — sudo dnf install rpm-build rpmdevtools" >&2
  exit 1
fi

VERSION="$(encrypchat_version)"
BUNDLE_NAME="encrypchat-${VERSION}-linux-x64"
TOP="${ROOT}/dist/.rpmbuild"
STAGE="${TOP}/stage"

build_linux_bundle

echo "==> Staging ${BUNDLE_NAME}"
rm -rf "${TOP}"
mkdir -p "${TOP}"/{SOURCES,SPECS,BUILD,BUILDROOT,RPMS,SRPMS}
stage_linux_bundle "${STAGE}/${BUNDLE_NAME}"

tar -C "${STAGE}" --owner=0 --group=0 --numeric-owner -czf \
  "${TOP}/SOURCES/${BUNDLE_NAME}.tar.gz" "${BUNDLE_NAME}"

# The sonames that live inside the bundle. rpm would otherwise generate a Requires for each
# one — they are linked, after all — and nothing on the system provides them, so the package
# would refuse to install. Computed here instead of listed in the spec so that adding a
# plugin cannot silently produce an uninstallable package.
BUNDLED_RE="^($(
  find "${STAGE}/${BUNDLE_NAME}" -name '*.so*' -printf '%f\n' \
    | sed 's/\./\\./g' \
    | sort -u \
    | paste -sd '|'
))"
echo "==> Private sonames: $(find "${STAGE}/${BUNDLE_NAME}" -name '*.so*' -printf '%f\n' | wc -l)"

echo "==> rpmbuild"
rpmbuild -bb "${ROOT}/packaging/rpm/encrypchat.spec" \
  --define "_topdir ${TOP}" \
  --define "app_version ${VERSION}" \
  --define "bundled_sonames ${BUNDLED_RE}"

RPM_PATH="$(find "${TOP}/RPMS" -name '*.rpm' -type f | head -1)"
[[ -n "${RPM_PATH}" ]] || { echo "error: rpmbuild produced no package" >&2; exit 1; }

# A dependency on a bundled library is the failure this package is most likely to have, and
# it does not show up until someone tries to install it on a clean machine.
echo "==> Requires"
rpm -qp --requires "${RPM_PATH}"
if rpm -qp --requires "${RPM_PATH}" | grep -Ei 'libapp\.so|libflutter_linux_gtk|libencrypchat_core|libwebrtc\.so|libsqlcipher'; then
  echo "error: the package depends on a library it carries privately — it will not install" >&2
  exit 1
fi

# Same idea in the other direction: these must not enter the system-wide namespace.
if rpm -qp --provides "${RPM_PATH}" | grep -Ei 'libapp\.so|libflutter_linux_gtk|libwebrtc\.so'; then
  echo "error: the package advertises its private libraries to the whole system" >&2
  exit 1
fi

DEST="${ROOT}/dist/$(basename "${RPM_PATH}")"
mv -f "${RPM_PATH}" "${DEST}"
rm -rf "${TOP}"

ls -lh "${DEST}"
echo "OK: ${DEST}"
echo "Install: sudo dnf install ${DEST}"
echo "Remove:  sudo dnf remove encrypchat"
echo "Note: unsigned, and no repository behind it — dnf will say so."
