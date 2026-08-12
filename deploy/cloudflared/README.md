# cloudflared (Cloudflare Tunnel) — Dokploy

Connector for **encrypchat.com**. Routes are set in Cloudflare Zero Trust; this stack only runs `cloudflared` on `dokploy-network` so it can reach `dokploy-traefik`.

## 1. Token

Cloudflare Zero Trust → Networks → Tunnels → your tunnel → install connector → copy **token**.

## 2. Cloudflare Public Hostnames

| Hostname | Service |
| --- | --- |
| `encrypchat.com` | `http://dokploy-traefik:80` |
| `www.encrypchat.com` | `http://dokploy-traefik:80` |

Domain spelling: **encrypchat.com** (with **y**).

## 3. Dokploy

1. Delete the old broken **cloudflared** app service if it cannot resolve Traefik.
2. **Create Service** → **Docker Compose**.
3. Repo: `fabioherrera/encrypchat`, branch `main`.
4. Compose file: `deploy/cloudflared/docker-compose.yml`
5. Environment (either name works):
   - `CLOUDFLARE_TUNNEL_TOKEN=<token>` (Dokploy-style), or
   - `TUNNEL_TOKEN=<token>`
6. Deploy.

Confirm network exists on the server:

```bash
docker network ls | grep dokploy
# expect: dokploy-network
```

If the network name differs, edit `name: dokploy-network` in the compose to match.

## 4. Verify

```bash
docker exec encrypchat-cloudflared getent hosts dokploy-traefik
docker logs encrypchat-cloudflared --tail 50
```

You should see an IP for Traefik and **no** `lookup dokploy-traefik ... misbehaving`.

Then open `https://encrypchat.com`.
