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
relay descarta `kind == 'call'` (el relay no autentica al remitente, así que un `from`
forjado podría hacer sonar la llamada como un contacto conocido).

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
