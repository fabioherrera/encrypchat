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
  → try_recv → decrypt(secret) → política de remitente → local_seal → UI
```

Sin relay en este camino: peer no conectado → error explícito (F5 añade relay opcional).

Las dos rutas (P2P y relay) convergen en `_acceptPayload`, el único punto que decide qué se
guarda: bloqueo, luego política de remitente —contacto, o bandeja de solicitudes acotada—, luego
escritura. Un `node_send` no bloquea la interfaz: sale por el isolate del núcleo
([audit-f10.md](audit-f10.md) F-6 y F-11).

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

Tokio TCP + handshake mutuo **EH02** (pin-first mientras la sesión vive; `sender_token` de cada trama atado al par autenticado). Desde `0.8.0` el transporte va cifrado con una clave de sesión derivada del handshake, una por sentido: la trama `EC04` entera viaja dentro del AEAD y por el socket solo se ve `len(4) || bytes opacos` (F-15). libp2p request-response deferred.  
Hasta `0.8.0` era EH01, cuya prueba se podía construir con la clave pública del verificador: no autenticaba nada (F-1 de [audit-f10.md](audit-f10.md)), y sus tramas iban en claro.  
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
