#!/usr/bin/env bash
# Build Linux x64 release bundle → dist/encrypchat-linux-x64-<version>.tar.gz
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

VERSION="$(encrypchat_version)"
OUT_NAME="encrypchat-linux-x64-${VERSION}"
BUNDLE="${ROOT}/apps/client/build/linux/x64/release/bundle"
STAGE="${ROOT}/dist/.stage-linux"
TARBALL="${ROOT}/dist/${OUT_NAME}.tar.gz"

echo "==> FFI (host)"
make -C "${ROOT}" build-ffi

echo "==> Flutter Linux release"
cd "${ROOT}/apps/client"
run_flutter pub get
ENCRYPCHAT_CORE_LIB="${ROOT}/apps/client/native/libencrypchat_core.so" \
  run_flutter build linux --release

if [[ ! -x "${BUNDLE}/encrypchat" ]]; then
  echo "error: missing binary ${BUNDLE}/encrypchat" >&2
  exit 1
fi

# Ensure core .so is in the bundle lib/ (CMake should install it; copy as safety net)
mkdir -p "${BUNDLE}/lib"
if [[ ! -f "${BUNDLE}/lib/libencrypchat_core.so" ]]; then
  cp -f "${ROOT}/apps/client/native/libencrypchat_core.so" "${BUNDLE}/lib/libencrypchat_core.so"
fi
test -f "${BUNDLE}/lib/libencrypchat_core.so"

echo "==> Staging ${OUT_NAME}"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/${OUT_NAME}"
cp -a "${BUNDLE}/." "${STAGE}/${OUT_NAME}/"

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
Icon=${PREFIX}/data/flutter_assets/assets/brand/logo-mark.png
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
tar -C "${STAGE}" -czf "${TARBALL}" "${OUT_NAME}"
rm -rf "${STAGE}"

ls -lh "${TARBALL}"
echo "OK: ${TARBALL}"
echo "Install: tar -xzf ${TARBALL} && cd ${OUT_NAME} && ./install.sh"
