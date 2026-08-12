# Encrypchat web (encrypchat.com)

Static Next.js export for Cloudflare Pages.

## Local

```bash
npm run dev
npm run build   # writes ./out
```

The CI gate is `make check-web` from the repo root: `rm -rf .next out && npm run build`. It
cleans because that is the only way `out/` — the artifact that gets deployed — is guaranteed to
match the commit being gated. A custom `distDir` was tried here and does **not** isolate the
build: it moves the export only, so `.next` was still shared with any running `next dev` and
`out/` was left stale while the gate went green. Do not run the gate with `next dev` up; both own
`.next` and the build fails at random with `Cannot find module for page`.

Fonts are self-hosted ([`src/app/fonts/`](src/app/fonts/README.md)) and telemetry is off, so the
build needs **no network** — verified with DNS and `fetch` blocked.

`npm audit` must stay at zero (`--audit-level=high` blocks in CI). Two advisories cannot be
reached through `next@15`'s own pins, so [`package.json`](package.json) carries `overrides` for
`postcss` and `sharp`. Both are build-time only here — `output: "export"` with
`images.unoptimized`, so `sharp` is never invoked — and the export is byte-identical with and
without them. Drop the overrides when a `next` release pins the patched versions itself.

## Deploy (Dokploy)

**Recommended:** build from **repo root** (Dokploy default):

| Field | Value |
| --- | --- |
| Context / build path | `.` or empty |
| Dockerfile | `Dockerfile` (root) |
| Port | `80` |
| Domain | `encrypchat.com` |

Auto-deploy on push to `main`.

Alternative: context `apps/web`, Dockerfile `Dockerfile`.

## Deploy (Cloudflare Pages)

```bash
npm run build
npx wrangler pages deploy out --project-name encrypchat
```

Point the custom domain **encrypchat.com** (and www → apex redirect) in the Cloudflare dashboard. DNS must be on Cloudflare for HTTPS + redirects.

## SEO

- Canonical base: `https://encrypchat.com`
- `/sitemap.xml`, `/robots.txt`
- OG image: `/og.png` (from brand logo)

## Contenido preparado y **no** publicado todavía

El modelo de amenazas (`docs/threat-model.md`) es la mejor pieza de contenido indexable que
tenemos sin publicar: responde en prosa citable las preguntas de intent alto (de qué protege,
de qué no, quién aprende qué) y es exactamente lo que busca alguien que compara mensajeros.

**El bloqueo de seguridad se levantó**: F-1 y F-2 de [`docs/audit-f10.md`](../../docs/audit-f10.md)
están cerrados en core y cliente, y el documento ya está marcado como publicable. Falta el trabajo
de sitio —la ruta no existe— y una revisión del auditor sobre el texto final. Queda un bloqueo que
no es nuestro: su sección «Reportar una vulnerabilidad» necesita un buzón de seguridad real, y no
publicamos direcciones que no funcionan.

El sitio hueco sigue reservado así:

| Pieza | Decisión ya tomada |
| --- | --- |
| Ruta | `/[locale]/security` — `security` como slug en las dos locales (no `/threat-model`, no `/es/seguridad`: el patrón del sitio es ruta única y contenido traducido) |
| Fuente | Adaptación de `docs/threat-model.md` a `Dictionary.security` en `src/i18n/{es,en}.ts`, con la misma forma que `privacy` / `terms` (`LegalDoc`), para que la paridad ES/EN la siga forzando TypeScript |
| Anclas | Ids estables e idénticos por locale, como en `privacy`: se van a citar desde fuera |
| Sitemap | Añadir a `APP_PATHS` (entra solo en `sitemap.xml` y con `hreflang`) |
| Enlaces internos | `privacy` → `security` en el bloque de páginas relacionadas, y `security` → `privacy` + `faq`; nada en la nav principal (no es intent de conversión) |
| Schema | Solo `WebPage` + `Organization`, como `privacy`. Sin `FAQPage` duplicado del de `/faq` |
| Bloqueo | Solo el buzón de seguridad de la sección 8 del documento. El bloqueo por F-1/F-2 ya no aplica |
