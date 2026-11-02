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
4. **Domains** (el recuadro azul pide Redeploy después de cambiar esto):

   | Campo | Valor |
   | --- | --- |
   | Service Name | `relay` |
   | Host | `relay.encrypchat.com` |
   | Path / Internal Path | `/` |
   | Container Port | **`8787`** (no 80: el proceso escucha 8787) |
   | HTTPS | off (el TLS lo termina Cloudflare) |

   Si dejas puerto **80**, Traefik habla con un puerto vacío y no llega a `/healthz`.
5. Env (el compose ya trae estos valores):

   ```
   ENCRYPCHAT_RELAY_TRUSTED_PROXIES=127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12
   ENCRYPCHAT_RELAY_REAL_IP_HEADER=cf-connecting-ip
   ```

   Sin puertos publicados: la única entrada es Traefik por el túnel.
6. Deploy.

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

Volumen persistente: `/data`. Env: las mismas dos variables, sin publicar el puerto.

## Cloudflare

Mismo túnel que `encrypchat.com`. Public hostname:

`relay.encrypchat.com` → `http://dokploy-traefik:80`

Si Dokploy ya tiene su conector (como el de `vps.elnerd.com`), usa ese túnel y no
despliegues `deploy/cloudflared`. Al mudarte, el hostname viejo debe salir del túnel
de Oracle para que el DNS apunte al nuevo.

## Comprobar

```bash
curl -sS https://relay.encrypchat.com/healthz
```

Debe responder `200`. En la app 1.0.6: Chats → ☁ → pega esa URL → Guardar.
A partir de 1.0.7 la app ya la trae encendida.
