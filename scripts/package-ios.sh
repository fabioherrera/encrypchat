#!/usr/bin/env bash
# iOS packaging (Phase 8 gap — needs macOS + Xcode + Apple signing).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cat <<EOF
Encrypchat — iOS packaging (not built on this host)

Gap: an IPA requires macOS + Xcode + CocoaPods + an Apple Developer team for
signing. This Linux host produces no placeholder IPA.

What is already wired for iOS (no Mac needed to verify):
  - ios/Runner/Info.plist has NSMicrophoneUsageDescription and
    NSCameraUsageDescription (WebRTC calls)
  - ios/Runner/GeneratedPluginRegistrant.m registers flutter_webrtc,
    image_picker_ios, sqflite_darwin and flutter_secure_storage
  - IPHONEOS_DEPLOYMENT_TARGET = 13.0 matches flutter_webrtc 1.6.0
    (WebRTC-SDK requires iOS 13+)
  - ios/Podfile is not committed; flutter generates it on the first iOS build

Missing (must be done on the Mac, once): crates/core is not linked into Runner.
lib/core/native_library.dart falls back to DynamicLibrary.process(), so the FFI
symbols must live in the app binary:

  rustup target add aarch64-apple-ios
  cargo build -p encrypchat_core --release --target aarch64-apple-ios
  # → target/aarch64-apple-ios/release/libencrypchat_core.a

  # In Xcode (ios/Runner.xcworkspace), Runner target:
  #   Build Phases ▸ Link Binary With Libraries ▸ + libencrypchat_core.a
  #   Build Settings ▸ Other Linker Flags ▸ add:
  #     -force_load \$(SRCROOT)/../../../target/aarch64-apple-ios/release/libencrypchat_core.a
  # -force_load is required: without it the linker dead-strips the exported
  # FFI symbols and DynamicLibrary.process() lookups fail at runtime.
  # For the simulator use aarch64-apple-ios-sim / x86_64-apple-ios instead.

Then:

  cd apps/client
  flutter pub get
  cd ios && pod install && cd ..
  flutter build ipa --release --tree-shake-icons   # needs a signing team
  # → build/ios/ipa/*.ipa ; distribute via TestFlight or ad-hoc

Verify before shipping: identity screen loads (FFI ok), a 1:1 call gets mic and
camera permission prompts, and photos attach through image_picker.

See docs/phase-8.md. No TestFlight link exists yet — do not invent one.
EOF
exit 2
