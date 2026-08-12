# Fase 6 — Media (fotos / archivos)

**Estado:** implementado (2026-08-12) — MVP foto 1:1 E2EE  
**Meta:** adjuntos cifrados; P2P preferido; relay solo si el ciphertext ≤ 256 KiB.

## Entregado

| Pieza | Detalle |
| --- | --- |
| Envelope `EM01` | `apps/client/lib/core/media_envelope.dart` |
| At-rest | `MediaStore` — `local_seal` bajo `support/media/` |
| Envío | `MessagingService.sendMedia` — gallery picker (max 1600px, q75); la copia temporal del picker se borra tras sellar |
| UI | botón imagen en chat; bubble con preview |
| Relay | fail-loud si blob cifrado > 256 KiB |

## Límites

| Camino | Límite |
| --- | --- |
| P2P | ciphertext ≤ ~16 MiB (frame core) |
| Relay | blob ≤ **256 KiB** (mismo tope del servicio) |

## Flujo

1. Pick imagen → resize → `EM01` → `encrypt` → EC04 P2P.  
2. Offline + relay: JSON v2 `{kind:media,data_b64,…}` cifrado; si supera 256KiB → error claro.  
3. Destino: decrypt → sellar archivo local → mostrar.

## Verificar

```bash
make build-ffi && make check-client
# Demo: 2 peers P2P, adjuntar foto en chat
```

## DoD

- [x] Foto 1:1 E2EE (P2P)
- [x] Fallo claro si supera límite relay
- [x] Archivos at-rest sellados (no plaintext en disco) — incluida la copia que deja el picker: se borra tras sellar y se barren los restos al arrancar (`core/media_picker.dart`)
- [x] `/auditor` file handling — [audit-f6-media.md](audit-f6-media.md)

## Gaps (no bloquean F7)

- Sin chunking multi-parte
- Sin video/docs genéricos en UI (API `sendMedia` sirve)
- Linux: `image_picker` puede pedir portal/xdg
- Auth `from` en relay = mismo gap F5 (pre-prod) 
