# Legal / compliance notes — Phase 7 WebRTC calls

**Status:** Readonly product counsel notes (not legal advice).  
**Date:** 2026-08-12  
**Scope:** Encrypchat 1:1 calls via `flutter_webrtc`; media P2P; public Google STUN only; no SFU / no Encrypchat media servers; SDP/ICE/invite over existing E2EE chat channel (P2P-only signaling).

> Escalate to licensed counsel before store submission or public marketing of calls.

## Permission purpose strings

| Platform | Keys / permissions | Honesty |
| --- | --- | --- |
| iOS | `NSMicrophoneUsageDescription`, `NSCameraUsageDescription` | OK for demo: content not uploaded to Encrypchat servers; do not imply zero network/third-party |
| Android | `RECORD_AUDIO`, `CAMERA`, `MODIFY_AUDIO_SETTINGS`, `BLUETOOTH_CONNECT` | Declare for live calls only |

**Safer phrasing:** “Call media is not sent to Encrypchat servers; it goes peer-to-peer. Connectivity helpers (STUN) may see IP/network metadata.”

## Do not claim

- Zero metadata / no third parties (public STUN)
- “Media never leaves the device” (packets go to peer)
- Impossible to intercept / 100% private / zero-knowledge calls
- Equating “no SFU” with “no servers at all”

## Store stubs (F9)

- [ ] Play Data safety + permission purposes for mic/camera
- [ ] App Privacy nutrition labels (Apple)
- [ ] Live privacy policy mentioning calls + STUN nuance
- [ ] Request mic/camera only at call start

## Verdict

| Context | Ready? |
| --- | --- |
| Demo LAN / sideload | **OK** |
| Play / App Store | **Blocked** until F9 + counsel pass |
