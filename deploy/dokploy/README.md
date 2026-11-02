# Encrypchat en Dokploy

Web y relay en un solo proyecto, detrás del túnel de Cloudflare. Sin IP pública ni puertos abiertos.

## 1. Cloudflare

**TURN** (Realtime → TURN Server → Create). Guarda el *Turn Token ID* y el *API Token*. Sin esto
todo funciona menos las llamadas entre las redes más estrictas. Pon una alerta de facturación:
incluye 1 000 GB al mes y luego cuesta $0.05/GB.

**Túnel.** Usa el conector que ya tiene ese Dokploy. No despliegues `deploy/cloudflared`.
En Zero Trust → Networks → Tunnels → ese túnel → Public Hostname:

| Hostname | Servicio | HTTP Host Header |
| --- | --- | --- |
| `encrypchat.com` | `http://dokploy-traefik:80` | `encrypchat.com` |
| `www.encrypchat.com` | `http://dokploy-traefik:80` | `www.encrypchat.com` |
| `relay.encrypchat.com` | `http://dokploy-traefik:80` | `relay.encrypchat.com` |

Si Cloudflare dice que el DNS ya existe, primero quita esos hostnames del túnel de Oracle.

## 2. Dokploy

1. Create Project `encrypchat` → Create Service → **Compose**.
2. Provider GitHub, repo `fabioherrera/encrypchat`, branch `main`.
3. Compose Path: `./deploy/dokploy/docker-compose.yml`.
4. Isolated Deployments: **apagado**.
5. Environment:

   ```
   ENCRYPCHAT_RELAY_TURN_KEY_ID=<Turn Token ID>
   ENCRYPCHAT_RELAY_TURN_API_TOKEN=<API Token>
   ```

6. Domains, con HTTPS apagado y path `/`:

   | Service | Host | Port |
   | --- | --- | --- |
   | `web` | `encrypchat.com` | 80 |
   | `web` | `www.encrypchat.com` | 80 |
   | `relay` | `relay.encrypchat.com` | 8787 |

7. Deploy.

El primer build compila Rust y Next, así que tarda varios minutos.

## 3. Comprobar

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://encrypchat.com/
curl -sS -o /dev/null -w '%{http_code}\n' https://relay.encrypchat.com/healthz
curl -sS https://encrypchat.com/update-manifest.json | head -c 80
```

Las dos primeras deben dar `200`. En la VM, confirma que la subred quede dentro de
`ENCRYPCHAT_RELAY_TRUSTED_PROXIES`:

```bash
docker network inspect dokploy-network --format '{{(index .IPAM.Config 0).Subnet}}'
```

Si no queda dentro, agrégala en Environment y vuelve a desplegar.

## 4. Publicar una versión

```bash
scripts/package-android.sh
# En el PC con Windows: scripts/package-windows.ps1
scripts/publish-update.sh \
  --base-url https://github.com/fabioherrera/encrypchat/releases/download/release-1.1.0 \
  --apk dist/encrypchat-android-arm64-1.1.0.apk \
  --windows-setup dist/encrypchat-windows-x64-1.1.0-setup.exe \
  --notes "Qué cambió"
```

Sube los paquetes a ese release y haz commit de `apps/web/public`. Dokploy publica el catálogo
firmado al desplegar. La etiqueta no debe empezar por `v`.

Las claves viven en `~/.encrypchat-release`, fuera del repo. Sin la clave de Android no se puede
actualizar la app, y sin la de firma no se puede publicar otra versión sin reinstalar. Guarda una
copia cifrada fuera de ese servidor.
