# Encrypchat web (encrypchat.com)

Static Next.js export for Cloudflare Pages.

## Local

```bash
npm run dev
npm run build   # writes ./out
```

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
