#!/usr/bin/env bash
# Shared helpers for Encrypchat packaging scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="${ROOT}/.tools"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${ROOT}/target}"
# Panic messages carry the source path of the file that raised them, and the crate registry
# lives under .tools/, so an unmodified build writes the builder's home directory into every
# shipped binary. Same string as the Makefile uses, on purpose: a different one would give
# cargo a different fingerprint and rebuild the world on each switch.
export RUSTFLAGS="--remap-path-prefix=${ROOT}=/encrypchat${RUSTFLAGS:+ ${RUSTFLAGS}}"
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

LINUX_BUNDLE="${ROOT}/apps/client/build/linux/x64/release/bundle"

# Build the Linux release bundle and make sure the core is inside it. Shared by the tarball
# and the RPM so the two cannot drift into shipping different binaries.
build_linux_bundle() {
  echo "==> FFI (host)"
  make -C "${ROOT}" build-ffi

  echo "==> Flutter Linux release"
  cd "${ROOT}/apps/client"
  run_flutter pub get
  # --tree-shake-icons is currently a no-op on desktop: flutter_tools passes
  # -dTreeShakeIcons="true" (quoted) to `flutter assemble`, so the subsetter stays
  # off and MaterialIcons ships whole (~1.6 MiB). Kept for when upstream fixes it.
  ENCRYPCHAT_CORE_LIB="${ROOT}/apps/client/native/libencrypchat_core.so" \
    run_flutter build linux --release --tree-shake-icons

  if [[ ! -x "${LINUX_BUNDLE}/encrypchat" ]]; then
    echo "error: missing binary ${LINUX_BUNDLE}/encrypchat" >&2
    exit 1
  fi

  # CMake should install the core; copy as a safety net so a stale build tree cannot
  # produce a package that starts and then dies with the core-missing banner.
  mkdir -p "${LINUX_BUNDLE}/lib"
  if [[ ! -f "${LINUX_BUNDLE}/lib/libencrypchat_core.so" ]]; then
    cp -f "${ROOT}/apps/client/native/libencrypchat_core.so" "${LINUX_BUNDLE}/lib/libencrypchat_core.so"
  fi
  test -f "${LINUX_BUNDLE}/lib/libencrypchat_core.so"
}

# Copy the bundle into $1, drop what no engine reads, and strip. Never touches the build
# tree: a developer running this should not end up with a stripped tree under build/.
stage_linux_bundle() {
  local dest="$1"
  rm -rf "${dest}"
  mkdir -p "${dest}"
  cp -a "${LINUX_BUNDLE}/." "${dest}/"

  local assets="${dest}/data/flutter_assets"
  if [[ -f "${assets}/NOTICES.Z" && -f "${assets}/NOTICES" ]]; then
    # Desktop engines read the gzipped NOTICES.Z; a plain NOTICES left over from
    # older builds in build/flutter_assets is never loaded (~1.3 MiB).
    rm -f "${assets}/NOTICES"
  fi

  echo "==> Stripping symbols (staged copy only)"
  local strip_bin before after
  strip_bin="$(command -v strip || command -v llvm-strip || true)"
  if [[ -n "${strip_bin}" ]]; then
    before="$(du -sb "${dest}" | cut -f1)"
    # Prebuilt plugin libs (libwebrtc.so, libsqlite3.so) ship with debug symbols.
    # Never fatal: a lib we cannot strip still ships, just bigger.
    find "${dest}" -name '*.so' -type f -exec "${strip_bin}" --strip-unneeded {} + || true
    "${strip_bin}" "${dest}/encrypchat" || true
    after="$(du -sb "${dest}" | cut -f1)"
    echo "stripped: $((before / 1048576)) MiB → $((after / 1048576)) MiB (uncompressed)"
  else
    echo "warn: no strip/llvm-strip on PATH — shipping unstripped libs" >&2
  fi

  # After stripping, so that this is the last thing to touch the files. Flutter's CMake bakes
  # the build tree into each plugin library's RUNPATH, and the sqlite3 package records an
  # absolute path to the SQLCipher it built. Both name the builder's home directory, and the
  # RUNPATH is worse than a leak: on the machine that produced the build those directories
  # exist, so an installed copy would prefer the libraries in the build tree over the ones it
  # shipped with — on the one machine where nobody would notice.
  echo "==> Rewriting build paths"
  "${ROOT}/scripts/fix-runpath.py" "${ROOT}" "${dest}"

  local assets_map="${dest}/lib/native_assets.json"
  if [[ -f "${assets_map}" ]] && grep -q "${ROOT}" "${assets_map}"; then
    # "system" means the loader resolves it by name, which reaches the copy in lib/ through
    # the engine's own $ORIGIN. Checked by running a staged bundle from another directory
    # with the build tree hidden: the encrypted database still opens.
    sed -i -E "s#\\[\"absolute\",\"${ROOT}[^\"]*/([^\"/]+)\"\\]#[\"system\",\"\\1\"]#g" "${assets_map}"
    if grep -q "${ROOT}" "${assets_map}"; then
      echo "error: ${assets_map} still points into the build tree" >&2
      exit 1
    fi
    echo "native assets: resolved by name instead of by build path"
  fi

  # Whatever is left is a leak nobody has looked for yet, and it should stop the build rather
  # than ship. One exception: the Dart AOT snapshot records the URI of the plugin registrant
  # that flutter_tools generates under .dart_tool, and gen_snapshot has no equivalent of
  # --remap-path-prefix. It is a single string naming a file that does not exist on the target,
  # so it is allowed by name — and anything else in the same file still fails.
  local leftovers
  leftovers="$(
    # Two details, both of which made this check lie during its first run. The match has to
    # stop at control bytes or it swallows the NUL that ends the string, and then no anchored
    # pattern can recognise what it found. And both greps need --binary-files=text, because
    # one that decides its input is binary prints "binary file matches" and drops the lines,
    # which turns the whole thing into a check that always passes.
    grep -rohE --binary-files=text "${ROOT}[^\"'[:space:][:cntrl:]]*" "${dest}" 2>/dev/null \
      | grep -v --binary-files=text '\.dart_tool/flutter_build/dart_plugin_registrant\.dart$' \
      | sort -u || true
  )"
  if [[ -n "${leftovers}" ]]; then
    echo "error: the build path is still readable inside the bundle:" >&2
    echo "${leftovers}" | sed 's#^#  #' >&2
    exit 1
  fi
}
