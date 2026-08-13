# Legal / compliance notes — Phase 7 WebRTC calls

**Status:** Readonly product counsel notes (not legal advice).  
**Date:** 2026-08-12  
**Scope:** Encrypchat 1:1 calls via `flutter_webrtc`; media P2P; public Google STUN only; no SFU / no Encrypchat media servers; SDP/ICE/invite over existing E2EE chat channel (P2P-only signaling).

> Escalate to licensed counsel before store submission or public marketing of calls.

## Permission purpose strings

| Platform | Keys / permissions | Honesty |
| --- | --- | --- |
| iOS | `NSMicrophoneUsageDescription`, `NSCameraUsageDescription` | Camera string covers QR scan of a contact card **and** video calls; frames processed on device. Do not imply zero network/third-party |
| Android | `RECORD_AUDIO`, `CAMERA`, `MODIFY_AUDIO_SETTINGS`, `BLUETOOTH_CONNECT` | Mic for live calls. Camera for live calls **and** for scanning a contact QR, only while that screen is open |

**Safer phrasing:** “Call media is not sent to Encrypchat servers; it goes peer-to-peer. Connectivity helpers (STUN) may see IP/network metadata.”

## Do not claim

- Zero metadata / no third parties (public STUN)
- “Media never leaves the device” (packets go to peer)
- Impossible to intercept / 100% private / zero-knowledge calls
- Equating “no SFU” with “no servers at all”
- Verified caller identity. The peer **is** cryptographically authenticated now — EH02 proves possession of the identity key on the direct route (core `0.8.0`, wired in the client), and signaling from a token that is not a contact is dropped without ringing — so “only your contacts can ring you” is accurate as a description of this device's behaviour. What is still **not** claimable is *verified* in the human sense: authentication binds a call to a key, not a key to a person, and there are no safety numbers and no key-change warning in the app yet (limitation 13 of [threat-model.md](threat-model.md)). Do not imply that a ringing contact has been identity-checked

## Store stubs (F9)

- [ ] Play Data safety + permission purposes for mic/camera
- [ ] App Privacy nutrition labels (Apple)
- [ ] Live privacy policy mentioning calls + STUN nuance
- [ ] Request mic only at call start; request camera at call start **or** when opening the contact QR scanner

## Verdict

| Context | Ready? |
| --- | --- |
| Demo LAN / sideload | **OK** |
| Play / App Store | **Blocked** until F9 + counsel pass |
