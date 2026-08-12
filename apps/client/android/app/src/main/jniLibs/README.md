# crates/core JNI libs (gitignored, produced by scripts/package-android.sh)
#
#   arm64-v8a/libencrypchat_core.so   <- the only ABI shipped today
#
# Release APKs are filtered to arm64-v8a (abiFilters in app/build.gradle.kts).
# To add another ABI: cross-compile crates/core for it, drop the .so in the
# matching folder, and build with -Pencrypchat.abis=arm64-v8a,<abi>.
# Shipping an ABI without its libencrypchat_core.so installs an app that
# crashes on FFI init.
#
# See docs/phase-3.md, docs/phase-8.md
