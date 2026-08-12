# Auditor review — Phase 5 blind relay

Readonly + post-fix notes (2026-08-12).

**Verdict:** OK for **LAN demo**. Not production-hardened.

## Holds

- Relay stores/returns opaque ciphertext only (client now enqueues E2EE JSON payload, not cleartext EC04)
- PoP ECDH + token↔pubkey bind + one-shot challenge
- TTL + delete-after-pull
- Prefer P2P; relay only on PeerOffline
- Call signaling never traverses the relay — the client refuses to enqueue it and
  drops `kind == 'call'` on pull (see `audit-f7-calls.md`)
- Application logs omit `dest_token` (no delivery graph); policy in `services/relay/README.md`
- Per-destination quota (200 blobs / 8 MiB pending, counted under the insert lock) and
  per-IP token bucket on `enqueue` / `challenge` / `pull`; all four values env-tunable

## Open (pre-production)

| Sev | Item |
| --- | --- |
| High→doc | Sender authenticity on relay path not EH01-grade (forged `from` inside ciphertext possible if attacker knows recipient pubkey). Scope is now text/media only: call signaling is refused on both relay directions |
| Medium | Challenge overwrite DoS — **mitigated**: `challenge` is rate-limited per IP (30/min default); a same-IP attacker can still overwrite a pending challenge within budget |
| Medium | Delete-before-client-durable-ack (message loss if drop after 200) |
| Low | Default HTTP (use TLS off-LAN) — client now shows a persistent warning instead of failing silently |
| Low | Quota rejection (`507`) tells a third-party sender the mailbox is near full; needs sender auth to close, not a different message |
| Low | Rate limits are per process / per IP: no protection against a distributed flood, and behind a proxy the proxy must limit (XFF not trusted) |

## P0 before public relay operators

1. Bind/sign sender on relay payloads  
2. TLS  
3. ~~Rate-limit challenges~~ — **done**: per-IP token bucket on `challenge`, `pull` and
   `enqueue`, plus a per-destination mailbox quota (`ENCRYPCHAT_RELAY_*`)  
