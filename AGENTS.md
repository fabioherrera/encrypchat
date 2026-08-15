# Encrypchat — AGENTS

Mensajería **P2P** cifrada de extremo a extremo. Cada dispositivo es cliente + nodo local. Contenido **zero-cloud** (chats/media/claves en el dispositivo).

**Roadmap:** [docs/roadmap.md](docs/roadmap.md) — fases 0–10, DoD y agentes.  
**Siguiente paso:** Probar `dist/` (F4–F7), cerrar F8 (Win/iOS) o completar los campos de operador de F9 (entidad legal, contacto, firma release).  
F7: [docs/phase-7.md](docs/phase-7.md) · F8: [docs/phase-8.md](docs/phase-8.md) · F9: [docs/phase-9.md](docs/phase-9.md) + [docs/legal-f9-stores.md](docs/legal-f9-stores.md).  
Deploy web: **Dokploy** construye el `Dockerfile` de la raíz y sirve el export con nginx; Cloudflare solo hace de túnel/CDN por delante. No es Cloudflare Pages y no hace falta `CLOUDFLARE_API_TOKEN` — ver [apps/web/README.md](apps/web/README.md#deploy-dokploy).

## Dominio y marca

- Sitio: **https://encrypchat.com**
- Marca: **Encrypchat** (con *y*). Variante `encripchat.com` → redirect si se registra.
- Tagline de marca: `DECENTRALIZED P2P CHAT | ZERO-CLOUD`
- Frase de producto: `P2P cuando se puede. Cifrado siempre. Sin nube de chats.`
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

## Cursor Cloud specific instructions

Preinstalled toolchains (baked into the VM image): Rust stable, Node 22, and
Flutter 3.44.9 / Dart 3.12.2 at `$HOME/flutter` (on `PATH` via `~/.bashrc`).
The startup update script only refreshes project dependencies
(`npm ci` in `apps/web`, `cargo fetch`, `flutter pub get` in `apps/client`).

Three dev-relevant products; use the `make` targets — they already handle the
non-obvious wiring (FFI `.so`, isolated `HOME`/`PUB_CACHE`, `ENCRYPCHAT_CORE_LIB`):

| Product | Lint / test / build | Run |
| --- | --- | --- |
| Rust core + relay (`crates/core`, `services/relay`) | `make check-rust` (fmt, clippy, tests, build) | `make run-relay` → listens `0.0.0.0:8787` (`ENCRYPCHAT_RELAY_ADDR` to change; API in [services/relay/README.md](services/relay/README.md)) |
| Web landing (`apps/web`) | `make check-web` | `make dev-web` → `localhost:3000` (locales `/en`, `/es`) |
| Flutter client (`apps/client`) | `make check-client` (pub get, `dart format`, `flutter test`) + `flutter analyze --no-fatal-infos` | GUI needs system deps — see caveat below |

Non-obvious caveats:

- **Rust must be ≥ 1.85 (stable).** A transitive dep needs `edition2024`; the
  older 1.83 that shipped in the base image fails clippy/build. The image's
  default `rustup` toolchain was bumped to current stable for this reason.
- **`flutter test` needs the core `.so`.** `make check-client` / `dev-client`
  build it first (`make build-ffi` → `apps/client/native/libencrypchat_core.so`)
  and set `ENCRYPCHAT_CORE_LIB`. Running `flutter test` by hand without that lib
  fails at FFI load.
- **Flutter desktop GUI does not run here.** `make build-client-linux` /
  `dev-client` (and any live GUI) need GTK dev headers, `ninja`, `pkg-config`,
  etc. that are **not** installed (Phase 8 / [docs/how-to-test.md](docs/how-to-test.md)).
  In this environment the client is validated via `flutter test` + `analyze`
  only, matching CI (`.github/workflows/check.yml`). `flutter analyze` runs with
  `--no-fatal-infos`, so info-level lints are expected and non-blocking.
- **Don't run `make check-web` while `make dev-web` is up:** both own `.next`
  and the build fails intermittently. Stop the dev server first.
