# Fase 4 — Mensajería P2P texto (online)

**Estado:** done (2026-08-12) — listo para demo LAN  
**Meta:** dos nodos online intercambian texto E2EE; cuerpos locales con AEAD (`db_key`).

## Entregado

| Pieza | Ubicación |
| --- | --- |
| Local AEAD | `crates/core/src/local_aead.rs` |
| Wire `EC04` | `crates/core/src/frame.rs` + Dart `wire_frame.dart` |
| Node TCP | `crates/core/src/net.rs` (Tokio; fail-loud PeerOffline; unregister on disconnect) |
| FFI `0.5.0+` | seal/open + node start/stop/send/recv/connect/listen_addr; EH01 auth hello |
| Flutter | chats list, chat 1:1, connect dialog, sealed message DB |
| Docs | este archivo + [ffi-contract.md](ffi-contract.md) + [audit-f4-messaging.md](audit-f4-messaging.md) |

## Flujo

```text
UI texto
  → local_seal(db_key) → SQLite body_sealed
  → encrypt(recipient_pub) → EC04 frame
  → node_send(peer_token)
receptor
  → try_recv → decrypt(secret) → local_seal → UI
```

Sin relay en este camino: peer no conectado → error explícito (F5 añade relay opcional).

## Demo 2 dispositivos (misma LAN)

1. Ambos: identidad + importar contacto del otro (QR/export).
2. Copiar multiaddr de Chats (icono link) / puerto.
3. Peer B: Conectar con IP LAN de A + puerto (o multiaddr `/ip4/…/tcp/…`).
4. Abrir chat y enviar — ticks navy = entregado; error = offline.

```bash
make build-ffi
make check-client
make package   # → dist/ con F4–F6
```

## Transporte

Tokio TCP + **EH01** authenticated hello (offer + E2EE proof; pin-first while live; frame `sender_token` bound to authenticated peer). libp2p request-response deferred.  
mDNS automático = deuda; dial manual vía `encrypchat_node_connect`.

## DoD

- [x] Core integración 2 nodos (`cargo test` net)
- [x] Plaintext solo en memoria UI; disco = `body_sealed` AEAD
- [x] UI chat 1:1 + estados sending/delivered/error
- [x] Gaps discovery documentados
- [x] `/auditor` framing + handshake — [audit-f4-messaging.md](audit-f4-messaging.md)
- [ ] Demo hardware 2 dispositivos (manual — tú pruebas)

## Nota libp2p

Se evaluó libp2p 0.54; RR fallaba en loopback dual-node. API de producto quedó estable para sustituir el transporte más adelante.

## Agentes

`/backend` · `/frontend` · `/auditor`
