# Auditor review — Phase 4 messaging

Readonly review (2026-08-12).

**Verdict:** P0 auth hello addressed in core `0.5.0` (EH01 + peer-bound frames). Re-audit before F5.

## Holds

- Wire payloads are E2EE ciphertext (product path)
- Message bodies on disk = `body_sealed` (`local_seal` + `db_key`)
- Peer offline → fail-loud (`PeerOffline`); no relay
- Docs honest: Tokio TCP (libp2p deferred)
- **EH01** hello: offer (token+pubkey+nonce) + encrypt proof; pin-first peer map; inbound frames require `sender_token == authenticated peer`

## P0 before Fase 5

1. ~~Authenticated hello (proof of token/key possession)~~ → EH01 in `net.rs` (`0.5.0`)
2. ~~Bind `sender_token` in frame to authenticated peer (reject spoof)~~ → `reader_loop` check

## Other

| Sev | Item |
| --- | --- |
| Medium | FFI `node_send` accepts opaque bytes (caller convention) |
| Low | UI “delivered” = TCP ACK, not crypto receipt |

Full narrative: auditor pass F4 (2026-08-12).
