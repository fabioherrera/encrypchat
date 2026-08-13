#!/usr/bin/env bash
# Build Linux x64 release bundle → dist/encrypchat-linux-x64-<version>.tar.gz
# Portable: extracts anywhere and installs into the user prefix, no root. For Fedora there
# is scripts/package-rpm.sh, which installs system-wide and uninstalls cleanly.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

VERSION="$(encrypchat_version)"
OUT_NAME="encrypchat-linux-x64-${VERSION}"
STAGE="${ROOT}/dist/.stage-linux"
TARBALL="${ROOT}/dist/${OUT_NAME}.tar.gz"

build_linux_bundle

echo "==> Staging ${OUT_NAME}"
stage_linux_bundle "${STAGE}/${OUT_NAME}"

cat > "${STAGE}/${OUT_NAME}/install.sh" <<'INSTALL'
#!/usr/bin/env bash
# Install Encrypchat Linux portable bundle into the user prefix.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${HOME}/.local/share/encrypchat"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/.local/share/applications"

echo "Installing Encrypchat → ${PREFIX}"
mkdir -p "${PREFIX}" "${BIN_DIR}" "${APP_DIR}"
# Replace install tree (keep other ~/.local/share contents intact)
find "${PREFIX}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -a "${HERE}/." "${PREFIX}/"
rm -f "${PREFIX}/install.sh"

ln -sfn "${PREFIX}/encrypchat" "${BIN_DIR}/encrypchat"

cat > "${APP_DIR}/encrypchat.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Encrypchat
Comment=DECENTRALIZED P2P CHAT | ZERO-CLOUD
Exec=${BIN_DIR}/encrypchat
Icon=${PREFIX}/data/flutter_assets/assets/brand/app-icon.png
Terminal=false
Categories=Network;InstantMessaging;
StartupWMClass=encrypchat
EOF

chmod +x "${PREFIX}/encrypchat" "${BIN_DIR}/encrypchat"
echo "Done. Run: encrypchat  (ensure ${BIN_DIR} is on PATH)"
echo "Desktop entry: ${APP_DIR}/encrypchat.desktop"
INSTALL
chmod +x "${STAGE}/${OUT_NAME}/install.sh" "${STAGE}/${OUT_NAME}/encrypchat"

echo "==> Creating ${TARBALL}"
tar -C "${STAGE}" --owner=0 --group=0 --numeric-owner -cf - "${OUT_NAME}" \
  | gzip -9 > "${TARBALL}"
rm -rf "${STAGE}"

ls -lh "${TARBALL}"
echo "OK: ${TARBALL}"
echo "Install: tar -xzf ${TARBALL} && cd ${OUT_NAME} && ./install.sh"
