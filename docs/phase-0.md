# Fase 0 — Checklist de ejecución

**Estado: done** (2026-08-11)

## Objetivo

Dejar el monorepo Encrypchat listo para desarrollar (builds vacíos, sin lógica de chat todavía).

## Árbol

```text
apps/client/       # Flutter (Android, iOS, Linux, Windows) — OK
apps/web/          # Next.js — landing SEO encrypchat.com — OK
crates/core/       # Rust library stub — OK
services/relay/    # Rust binary stub — OK
docs/              # roadmap + phase docs — OK
```

## Tareas

1. [x] `.gitignore`
2. [x] `LICENSE` placeholder
3. [x] `apps/client` — `flutter create` (android, ios, linux, windows)
4. [x] `crates/core` — cargo library + workspace
5. [x] `apps/web` — Next.js App Router
6. [x] `services/relay` — Rust stub + README
7. [x] `Makefile` — `check` / `dev-web` / `dev-client`
8. [x] `README.md` raíz
9. [x] CI stub `.github/workflows/check.yml`
10. [x] Auditor smoke: sin secretos

## DoD

- [x] Carpetas del monorepo
- [x] Flutter / Cargo / Next.js verificados (`make check`)
- [x] README + AGENTS + roadmap
- [x] Sin secretos en repo

## Gaps documentados

- `flutter build linux` necesita CMake/GTK del host → Fase 8
- Next.js puede reportar advisories npm; bump en F1 si hace falta

## Siguiente

Ejecutar **Fase 1** (SEO landing) y/o **Fase 2** (identidad/crypto).
