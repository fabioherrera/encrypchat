# Pre-F7 readiness — qué está cerrado vs qué es tuyo

Checklist antes de **Fase 7 (WebRTC)**. Actualizado 2026-08-12.

## De mi parte (código / docs) — CERRADO

| Fase | Estado | Artefacto |
| --- | --- | --- |
| 0 Fundación | Done | monorepo + Makefile |
| 1 Landing SEO | Done (código) | `apps/web` — HTTPS live = operador CF |
| 2 Crypto local | Done | tests + audit-f2 |
| 3 Shell + FFI + DB | Done | phase-3; packages F8 |
| 4 Chat P2P + EH01 | Done | phase-4 + audit-f4 |
| 5 Relay ciego | Done (demo LAN) | phase-5 + audit-f5 |
| 6 Media fotos | Done (demo LAN) | phase-6 + audit-f6 |
| 8 Packaging corte | Linux+Android en `dist/` | phase-8 (Win/iOS gap OK) |

Verificación automática: `make check` + `make package`.

## Tuyo (prueba manual) — ANTES o EN PARALELO a F7

1. Instalar `dist/` Linux y/o Android ([how-to-test.md](how-to-test.md))
2. Demo 2 dispositivos: texto P2P, reconnect, foto, relay offline
3. Anotar fallos → los arreglamos antes/durante F7

## NO bloquean F7 (documentados a propósito)

| Ítem | Quién |
| --- | --- |
| Deploy HTTPS encrypchat.com | Operador (`CLOUDFLARE_API_TOKEN`) |
| Windows / iOS instaladores | Host Win/Mac — F8 gap |
| SQLCipher full-file | Hardening F10 |
| Auth `from` en relay (spoof) | Pre-prod — audit-f5/f6 |
| Firma Play/App Store | F9 |

## Siguiente fase

**F7 — Llamadas WebRTC** cuando digas, tras (o durante) tus pruebas de `dist/`.
