# Fase 5 — Relay ciego (offline)

**Estado:** implementado backend + cliente (2026-08-12) — listo para demos LAN; no “production-hardened”  
**Meta:** buzón HTTP opaco (ciphertext + token + TTL) con pull PoP; sin plaintext de contenido en el relay.

## Entregado

| Pieza | Ubicación |
| --- | --- |
| Relay axum | `services/relay` |
| PoP ECDH | `crates/core` `pop.rs` + FFI `0.6.0` |
| Flutter | `relay_client.dart` + `messaging_service` (☁ URL) |
| Docs ops | `services/relay/README.md` |

## Flujo

1. Preferir P2P (`node_send`).  
2. Si `PeerOffline` y hay URL de relay: `encrypt(JSON{from,body})` → `POST /v1/enqueue` (solo ciphertext).  
3. Receptor: poll challenge → `pop_proof` → pull → decrypt → UI (`viaRelay`).

```bash
cargo run -p encrypchat_relay
# App: Chats → ☁ → http://<IP>:8787
```

## Qué ve el relay (honesto)

| Ve | No ve |
| --- | --- |
| `dest_token`, tamaño blob, tiempos, TTL | Plaintext del mensaje |
| | Claves privadas |

**Limitación conocida (pre-prod):** el campo `from` va *dentro* del ciphertext (solo el destinatario lo lee) pero **no** está firmado como EH01; un atacante que conoce la pubkey del destinatario podría forjar un blob. Mitigación futura: firma / AAD con identidad del remitente. Para demos de confianza LAN es aceptable; no claim “imposible spoofear remitente vía relay”.

## DoD

- [x] Receptor apagado → enqueue; al encender pull entrega (demo LAN)
- [x] Relay no descifra contenido (tests + diseño)
- [x] TTL y borrado post-pull
- [x] Cliente Flutter enqueue/pull
- [x] Copy landing ya habla de relay ciego opcional (claims matizados)
- [x] `/auditor` — ver [audit-f5-relay.md](audit-f5-relay.md)

## Env

| Variable | Default |
| --- | --- |
| `ENCRYPCHAT_RELAY_ADDR` | `0.0.0.0:8787` |
| `ENCRYPCHAT_RELAY_DB` | `./data/relay.sqlite` |
