# Auditor review — Phase 4 messaging

Readonly re-audit after EH01 (2026-08-12).

> **Corrección (2026-08-12, pase de core).** Este informe da por buena la autenticación de
> EH01, y es falso. "Descifrar la prueba del par con el secreto local" **no** prueba posesión
> de la clave ofrecida: la prueba se cifraba hacia el verificador, así que bastaba la clave
> pública de la víctima para construirla (F-1 de [audit-f10.md](audit-f10.md)). Todo lo que
> esta página marca como cerrado por EH01 estuvo abierto hasta EH02 (`0.8.0`), incluido el
> bind del `sender_token` de `EC04`, que ataba la trama a una sesión que no estaba autenticada.

**Verdict:** PASS WITH NOTES — DoD “framing + handshake” **CLOSED for demo**.
Core `0.5.0+`: EH01 auth hello + EC04 `sender_token` bound to authenticated peer.
Peer unregister on reader exit (reconnect) applied in core after this pass.

## Holds

- Wire payloads are E2EE ciphertext (product P2P path)
- Message bodies on disk = `body_sealed` (`local_seal` + `db_key`)
- Peer unknown/offline → fail-loud (`PeerOffline`) on P2P send
- Docs honest: Tokio TCP (libp2p deferred)
- **EH01** hello: offer (token+pubkey+nonce) + reciprocal E2EE proofs;
  decrypting the peer’s proof with the local secret proves possession of the
  claimed offer key; token must match pubkey hash; pin-first peer map while live;
  inbound frames require `sender_token == authenticated peer`

## P0 status

| Item | Demo | Production |
| --- | --- | --- |
| Authenticated hello (key possession) | Closed — EH01 | Closed |
| Bind frame `sender_token` to session | Closed — `reader_loop` | Closed |
| Peer map lifecycle / reconnect | Closed — unregister on reader exit | Watch races during replace |

## Other

| Sev | Item |
| --- | --- |
| Medium | FFI `node_send` accepts opaque bytes (caller convention) |
| Medium | `node_connect` TOFU (`expected_remote: None`); prefer contact-pinned dial |
| Low | UI “delivered” = TCP ACK, not crypto receipt |
| Low | No automated test for spoofed frame `sender_token` |
| Low | Message AEAD AAD does not bind sender (P2P mitigated by session bind) |

## DoD

- [x] `/auditor` framing + handshake (demo)
- [x] Peer unregister / reconnect after disconnect

Full narrative: auditor re-pass F4 EH01 (2026-08-12).
