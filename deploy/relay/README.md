# Relay público — `relay.encrypchat.com`

Para que dos Encrypchat hablen **sin estar en la misma Wi‑Fi**. Solo ciphertext.

## Dokploy

Estos ficheros tienen que estar **en GitHub** (`main`). Si solo existen en tu
computador, el clone de Dokploy no los ve.

1. Create Service → **Docker Compose** → source **GitHub** (mismo repo que el sitio).
2. Branch: `main`.
3. **Compose path** (relativo al repo, tal cual):

   `deploy/relay/docker-compose.yml`

   No pongas `/home/iofab/cursor/EncrypChat.com/...`. Esa ruta es de tu Fedora;
   dentro de Dokploy no existe, y el log sale `Compose file not found`.
4. **Domains:** añade `relay.encrypchat.com` y elige el servicio `relay`.
   Sin dominio, Dokploy a veces miente con el mismo error.
5. Puerto: `8787`.
6. Env: `ENCRYPCHAT_RELAY_TRUSTED_PROXIES=127.0.0.1,::1,172.16.0.0/12`
7. Deploy.

El build usa la **raíz del repo** (`context: ../..`). El `.dockerignore` de
la raíz no debe listar `crates` ni `services`: si los ignora, Docker copia
`Cargo.toml` y luego falla con `"/services/relay": not found`.

### Otra vía (igual que encrypchat.com)

Create Service → **Application** → Dockerfile:

| Campo | Valor |
| --- | --- |
| Context | `.` |
| Dockerfile | `services/relay/Dockerfile` |
| Port | `8787` |
| Domain | `relay.encrypchat.com` |

Volumen persistente: `/data`. Env: la misma `TRUSTED_PROXIES`.

## Cloudflare

Mismo túnel que `encrypchat.com`. Public hostname:

`relay.encrypchat.com` → `http://dokploy-traefik:80`

## Comprobar

```bash
curl -sS https://relay.encrypchat.com/healthz
```

Debe responder `200`. En la app 1.0.6: Chats → ☁ → pega esa URL → Guardar.
A partir de 1.0.7 la app ya la trae encendida.
