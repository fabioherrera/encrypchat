# Fase 7 — Llamadas audio/video (WebRTC)

**Estado:** implementado (2026-08-12) — MVP 1:1 P2P  
**Meta:** llamada 1:1; señalización E2EE por canal Encrypchat; media WebRTC sin SFU.

## Entregado

| Pieza | Detalle |
| --- | --- |
| Señal | `call_signal.dart` JSON `kind:call` (invite/accept/reject/hangup/sdp/ice) |
| WebRTC | `CallService` + `flutter_webrtc` |
| UI | `CallPage` + banner entrante en `CallOverlayHost`; botones en chat |
| STUN | `stun.l.google.com:19302` (+ stun1) — público |
| Permisos | Android mic/cam; iOS usage strings |
| Docs | [audit-f7-calls.md](audit-f7-calls.md) · [legal-f7-calls.md](legal-f7-calls.md) |

## Flujo

1. Peer A/B conectados P2P (EH01).  
2. Chat → 📞 / 📹 → invite + SDP offer (E2EE).  
3. Contestar → answer + ICE (P2P only).  
4. Media DTLS-SRTP directa entre peers — **no** pasa por Encrypchat.

## Política relay

Señalización de llamada es **P2P-only** hasta auth de remitente en relay (F5). ICE nunca por relay.

Se aplica en los dos sentidos: `sendCallSignal` no tiene rama de relay y el inbound de
relay descarta las señales de llamada.

**Corrección (0.8.0).** Esta política nunca protegió de la suplantación: el camino P2P tenía
el mismo agujero, porque EH01 tampoco probaba posesión de la clave (F-1 de
[audit-f10.md](audit-f10.md)). Con EH02 y `ECS1` las dos rutas autentican al remitente.

**Estado con el cliente cableado.** El anti-replay por `msg_id` ya está (relay), así que el
motivo original de la política dejó de aplicar. Sigue P2P-only por una razón distinta y no
criptográfica: un `invite` sellado se puede pull-ear horas después y sonaría por una llamada que
ya no existe, y contestarlo entregaría micro y cámara hacia un par que no está conectado.
Habilitarlo pide expirar la señal por su `sent_at` (segundos, no días), descartar todo lo que no
sea `invite`/`reject` fuera de una llamada viva, y decidir qué hace la UI con un timbre perdido.
Se valora aparte; no se activó en el mismo cambio.

## DoD

- [x] Audio + video en cliente (Linux/Android targets; demo LAN)
- [x] Sin SFU / sin media en servidores Encrypchat
- [x] `/auditor` — [audit-f7-calls.md](audit-f7-calls.md)
- [x] `/legal` notes — [legal-f7-calls.md](legal-f7-calls.md)

## Gaps

| Ítem | Nota |
| --- | --- |
| TURN | No — NAT estricto puede fallar |
| Windows / iOS runtime | Depende de host/toolchain F8 |
| FLAG_SECURE | Pendiente (screenshots) |
| Background call | No |
| Linux PulseAudio | `libpulse` opcional (solo loopback display; mic vía PipeWire/ALSA) |

## Verificar

```bash
make build-ffi && make check-client
# 2 peers P2P en LAN → chat → llamada audio/video
```
