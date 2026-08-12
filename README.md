# Encrypchat

P2P encrypted chat. Each device is a client + local node. Content stays on-device (**zero-cloud**).

| | |
| --- | --- |
| Site | https://encrypchat.com |
| Tagline | DECENTRALIZED P2P CHAT \| ZERO-CLOUD |
| Platforms | Android · iOS · Linux (Fedora) · Windows |

## Layout

```text
apps/client/       Flutter multiplatform client
apps/web/          Next.js landing (SEO) for encrypchat.com
crates/core/       Rust core (identity, E2EE, libp2p)
services/relay/    Blind relay stub (Phase 5)
docs/              Roadmap and phase checklists
```

## Docs

- [AGENTS.md](AGENTS.md) — Cursor agent routing
- [docs/roadmap.md](docs/roadmap.md) — phases 0–10
- [docs/phase-0.md](docs/phase-0.md) — foundation checklist

## Prerequisites

- Rust (stable) + Cargo
- Node.js 20+ + npm
- Flutter 3.x (`flutter` on PATH, or clone SDK into `.tools/flutter`)

## Deploy (Dokploy)

Repo: `https://github.com/fabioherrera/encrypchat.git`

**Landing**

| Field | Value |
| --- | --- |
| Context | `.` |
| Dockerfile | `Dockerfile` |
| Port | `80` |
| Branch | `main` |

**Cloudflared tunnel**

| Field | Value |
| --- | --- |
| Type | Docker Compose |
| Compose path | `deploy/cloudflared/docker-compose.yml` |
| Env | `TUNNEL_TOKEN` |

Guide: [`deploy/cloudflared/README.md`](deploy/cloudflared/README.md).  
CF routes: `encrypchat.com` / `www` → `http://dokploy-traefik:80`.

## Commands

```bash
make check          # rust tests + web build + flutter analyze
make check-rust
make check-web
make check-client
make dev-web        # Next.js on localhost
make dev-client     # Flutter (linux device by default)
```

## Phase status

See [docs/roadmap.md](docs/roadmap.md). Current scaffolding is **Phase 0** (empty builds, no chat logic yet).

## License

See [LICENSE](LICENSE) (placeholder until public release).
