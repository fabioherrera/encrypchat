# Auditor review — Phase 7 WebRTC calls (signaling)

Readonly audit (2026-08-12). Scope: `call_signal.dart`, `call_service.dart`,
`messaging_service.dart` (`sendCallSignal` + inbound demux), `call_page.dart`,
`call_overlay_host.dart`, [phase-7.md](phase-7.md).

**Verdict:** PASS WITH NOTES — OK for LAN/demo P2P. Not production-hardened
for public relay (call signaling disabled on relay by design until F5 sender-auth).

## Holds

- Media path is P2P WebRTC; iceServers = public Google STUN only (no SFU, no
  Encrypchat media/TURN server)
- Signaling encrypted at origin before P2P frame
- Call signals demuxed out of chat DB (not persisted as bubbles)
- Call signaling **P2P-only in both directions** until relay sender-auth: `sendCallSignal`
  has no relay branch (the `allowRelay` escape hatch was removed) and `_handleRelayBlob`
  drops inbound `kind == 'call'`, so a forged `from` cannot ring the callee
- Non-invite inbound requires `fromToken == peer.token`
- Invite ignored unless `fromToken` maps to a known contact
- SDP/ICE size caps in `CallSignal.decode`
- STUN third-party metadata: document honestly in privacy/claims

## Findings

| Sev | Item |
| --- | --- |
| Medium | NAT without TURN → call fail (product); do not invent TURN |
| Low | Stale invite if peer reconnects mid-ring (no call TTL) |
| Low | No FLAG_SECURE / screen-capture hardening on call UI |
| Low | Offer/invite reorder edge cases |

## P0 before production

1. Optional: re-enable relay signaling only after bind/sign sender (F5). Both the send
   and the pull path must be re-opened together — do not restore only one side
2. FLAG_SECURE (Android) / equivalent where available
3. Privacy copy: no “zero metadata” while using public STUN

## Demo vs release

- Demo/LAN (P2P, trusted contacts): acceptable
- Public release: blocked on F5 sender-auth (if relay calls wanted) + F9 privacy labels
