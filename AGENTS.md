# Encrypchat — AGENTS

Mensajería **P2P** cifrada de extremo a extremo. Cada dispositivo es cliente + nodo local. Contenido **zero-cloud** (chats/media/claves en el dispositivo).

**Roadmap:** [docs/roadmap.md](docs/roadmap.md) — fases 0–10, DoD y agentes.  
**Siguiente paso:** Probar `dist/` (F4–F7), cerrar F8 (Win/iOS) o completar los campos de operador de F9 (entidad legal, contacto, firma release).  
F7: [docs/phase-7.md](docs/phase-7.md) · F8: [docs/phase-8.md](docs/phase-8.md) · F9: [docs/phase-9.md](docs/phase-9.md) + [docs/legal-f9-stores.md](docs/legal-f9-stores.md).  
F1 deploy: `CLOUDFLARE_API_TOKEN` + `apps/web/out`.

## Dominio y marca

- Sitio: **https://encrypchat.com**
- Marca: **Encrypchat** (con *y*). Variante `encripchat.com` → redirect si se registra.
- Tagline: `DECENTRALIZED P2P CHAT | ZERO-CLOUD`
- Logo: `encrypchat logo.png`
- **UI aprobada (light):** [docs/design/design-system.md](docs/design/design-system.md) — tokens + mockup chat; usar en landing, Flutter y marca. Dark pendiente.

## Plataformas (primera clase)

| OS | Cliente |
| --- | --- |
| Android | Flutter `apps/client` |
| iOS | Flutter `apps/client` |
| Linux (Fedora) | Flutter `apps/client` |
| Windows | Flutter `apps/client` |

`apps/web` = landing/SEO/descargas en encrypchat.com — **no** es el chat.

## Stack objetivo

| Capa | Tech |
| --- | --- |
| UI | Flutter |
| Core | Rust + libp2p + E2EE (`crates/core`) |
| DB local | **SQLCipher** en el dispositivo (fichero completo, AES-256; clave derivada de `db_key` del almacén seguro del SO) + cuerpos de mensaje y media sellados con AEAD encima. No protege con el dispositivo desbloqueado y el llavero accesible ([audit-f3-storage.md](docs/audit-f3-storage.md)) |
| A/V | WebRTC P2P |
| Offline | Relay ciego (`services/relay`) |
| Web | Next.js (`apps/web`) |

## Subagentes Cursor

| Invocar | Rol | Writable |
| --- | --- | --- |
| `/orquestador` | Parte tareas multi-capa / multi-plataforma | sí |
| `/frontend` | Flutter UI + marketing UI | sí |
| `/backend` | Core Rust, FFI, relay, crypto | sí |
| `/auditor` | Seguridad e invariantes | **readonly** |
| `/seo` | **encrypchat.com** — SEO/AEO (prioridad alta) | sí |
| `/legal` | Privacy, ToS, claims, stores | **readonly** |

Reglas: [`.cursor/rules/encrypchat.mdc`](.cursor/rules/encrypchat.mdc), [`.cursor/rules/cursor-agents-routing.mdc`](.cursor/rules/cursor-agents-routing.mdc).  
Perfiles: [`.cursor/agents/`](.cursor/agents/).

## Orden seguro

1. Duda / diff sensible → `/auditor`
2. Implementar con `/frontend` o `/backend` (o `/orquestador` si es multi-capa)
3. Cambios en encrypchat.com → **`/seo` obligatorio**; claims → `/legal`
4. Tras crypto/relay/FFI → `/auditor` otra vez

## Invariantes (resumen)

1. Sin plaintext de chats en servidores  
2. E2EE en origen; relay solo ciphertext  
3. Identidad por token (clave pública)  
4. Datos en el dispositivo  
5. Claims honestos  
6. Paridad Android / iOS / Linux / Windows  
