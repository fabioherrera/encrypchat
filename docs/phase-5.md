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
2. Si `PeerOffline` y hay URL de relay: `sealed_seal(payload)` → `POST /v1/enqueue` (blob `ECS1`,
   solo ciphertext). El payload es el mismo que lleva P2P y **no** declara remitente.  
3. Receptor: `POST /v1/challenge` (sin cuerpo) → `pop_proof` → `POST /v1/pull` con el
   `challenge_id` recibido → `sealed_open` (remitente autenticado) → anti-replay por `msg_id`
   → UI (`viaRelay`).

El desafío ya no se pide "para un token": iba indexado por destinatario y cualquiera podía
sobreescribir el tuyo y dejarte el buzón inaccesible ([audit-f10.md](audit-f10.md) F-8).
Cambia el contrato HTTP; el cliente Dart tiene que actualizarse.

```bash
cargo run -p encrypchat_relay
# App: Chats → ☁ → http://<IP>:8787
```

## Qué ve el relay (honesto)

| Ve | No ve |
| --- | --- |
| `dest_token`, tamaño blob, tiempos, TTL | Plaintext del mensaje |
| | Claves privadas |

**Limitación cerrada (2026-08-12).** El campo `from` declarado dentro del ciphertext dejaba forjar
un blob a cualquiera con la pubkey del destinatario ([audit-f10.md](audit-f10.md) F-2). Ya no
existe: el remitente sale del criptograma (`ECS1`, [ffi-contract.md](ffi-contract.md)) y solo el
destinatario puede verificarlo, así que tampoco es un recibo público de autoría. Lo que sigue
siendo cierto: el relay ve `dest_token`, tamaños y tiempos, y un blob capturado se puede reencolar
— lo corta el conjunto de `msg_id` vistos del cliente, no el relay.

**Un metadato menos (2026-08-12).** `/v1/challenge` ya no lleva `dest_token`, así que pedir
desafío deja de decirle al relay qué buzón está a punto de leerse. Sigue viéndolo en el pull.

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
