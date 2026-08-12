#!/usr/bin/env bash
# Build Android arm64 release APK → dist/encrypchat-android-arm64-<version>.apk
#
# Signing: release uses android/key.properties when present, otherwise the debug
# keystore (sideload testing only — do NOT publish a debug-signed APK).
#
# Size: arm64-v8a only. crates/core is cross-compiled for aarch64 only, so any
# other ABI in the APK would ship a Flutter engine that cannot load the FFI core.
# abiFilters in android/app/build.gradle.kts also drops the extra ABIs that come
# from plugin AARs (flutter_webrtc ships x86_64 + armeabi-v7a jingle libs).
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

VERSION="$(encrypchat_version)"
OUT_APK="${ROOT}/dist/encrypchat-android-arm64-${VERSION}.apk"
ANDROID_HOME="${ANDROID_HOME:-${HOME}/Android/Sdk}"
export ANDROID_HOME
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME}}"

if [[ -x "${TOOLS}/jdk-21/bin/javac" ]]; then
  export JAVA_HOME="${TOOLS}/jdk-21"
  export PATH="${JAVA_HOME}/bin:${PATH}"
fi

NDK_VERSION="${ANDROID_NDK_VERSION:-28.2.13676358}"
NDK="${ANDROID_NDK_HOME:-${ANDROID_HOME}/ndk/${NDK_VERSION}}"
if [[ ! -d "${NDK}" ]]; then
  echo "error: NDK not found at ${NDK}" >&2
  echo "Set ANDROID_NDK_HOME or install NDK under \$ANDROID_HOME/ndk/" >&2
  exit 1
fi
export ANDROID_NDK_HOME="${NDK}"

API="${ANDROID_API:-24}"
TOOLCHAIN="${NDK}/toolchains/llvm/prebuilt/linux-x86_64"
export CC_aarch64_linux_android="${TOOLCHAIN}/bin/aarch64-linux-android${API}-clang"
export AR_aarch64_linux_android="${TOOLCHAIN}/bin/llvm-ar"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="${TOOLCHAIN}/bin/aarch64-linux-android${API}-clang"

echo "==> Rust core (aarch64-linux-android)"
rustup target add aarch64-linux-android >/dev/null
cd "${ROOT}"
cargo build -p encrypchat_core --release --target aarch64-linux-android

JNIDIR="${ROOT}/apps/client/android/app/src/main/jniLibs/arm64-v8a"
mkdir -p "${JNIDIR}"
cp -f "${CARGO_TARGET_DIR}/aarch64-linux-android/release/libencrypchat_core.so" \
  "${JNIDIR}/libencrypchat_core.so"
echo "jniLibs → ${JNIDIR}/libencrypchat_core.so"

if [[ -f "${ROOT}/apps/client/android/key.properties" ]]; then
  echo "==> Flutter APK release (signing with android/key.properties)"
else
  echo "==> Flutter APK release (debug-signing — sideload only)"
fi
cd "${ROOT}/apps/client"
run_flutter pub get
run_flutter build apk --release --target-platform android-arm64 --tree-shake-icons

SRC_APK="${ROOT}/apps/client/build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -f "${SRC_APK}" ]]; then
  echo "error: missing ${SRC_APK}" >&2
  exit 1
fi

# Fail loud if an unusable ABI slipped in: without a matching libencrypchat_core.so
# the app would install and then crash on FFI init.
if command -v unzip >/dev/null 2>&1; then
  EXTRA_ABIS="$(unzip -Z1 "${SRC_APK}" 'lib/*' 2>/dev/null \
    | cut -d/ -f2 | sort -u | grep -v '^arm64-v8a$' || true)"
  if [[ -n "${EXTRA_ABIS}" ]]; then
    echo "error: APK contains non-arm64 ABIs without an FFI core: ${EXTRA_ABIS}" >&2
    exit 1
  fi
  test -n "$(unzip -Z1 "${SRC_APK}" 'lib/arm64-v8a/libencrypchat_core.so' 2>/dev/null)" || {
    echo "error: APK is missing lib/arm64-v8a/libencrypchat_core.so" >&2
    exit 1
  }
fi

cp -f "${SRC_APK}" "${OUT_APK}"
ls -lh "${OUT_APK}"
echo "OK: ${OUT_APK}"
echo "Install: adb install -r ${OUT_APK}"
if [[ ! -f "${ROOT}/apps/client/android/key.properties" ]]; then
  echo "Note: debug-signed for sideload testing only — not for Play Store."
fi
