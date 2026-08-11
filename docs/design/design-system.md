# Encrypchat — Design system (aprobado)

**Estado:** UI chat light **aprobada** (2026-08-11). Fuente de verdad visual para landing (`apps/web`), app Flutter (`apps/client`) y materiales de marca.

**Referencias:**

- Chat aprobado: [chat-light-aprobado.png](./chat-light-aprobado.png)
- Lista (orientación): [chats-list-light.png](./chats-list-light.png)
- Logo (colores / isotipo, no en chrome del chat): `encrypchat logo.png` en raíz del monorepo

## Principios

1. **Light por defecto.** Dark se define después con los mismos tokens invertidos.
2. Logo = **referencia de color y marca**. No poner el escudo en el header del chat (igual que WhatsApp/Telegram).
3. Híbrido **WhatsApp densidad + Telegram chrome limpio**, con estados Encrypchat (P2P / relé / offline).
4. Azul marino serio; sin purple glow, sin verdosos WhatsApp como acento primario.

## Tokens (light)

| Token | Hex | Uso |
| --- | --- | --- |
| `navy` | `#0F2744` | Marca, send, iconos, unread, avatar fill |
| `navy-mid` | `#1A365D` | Hover / acento secundario (logo) |
| `ink` | `#14233A` | Texto principal |
| `muted` | `#5A6B7D` | Previews, timestamps, subtítulos |
| `paper` | `#FFFFFF` | Superficies, incoming bubbles, composer |
| `canvas` | `#F4F6F8` | Fondo chat / página |
| `bubble-out` | `#E6ECF4` | Mensajes salientes |
| `p2p` | `#1B7F4E` | Online / P2P |
| `relay` | `#C47B1A` | Vía relé |
| `offline` | `#8A94A0` | Sin conexión |
| `hairline` | `navy @ 12%` | Divisores |

## Chat UI (contrato)

- Header: back · avatar · nombre · `P2P · en línea` · call / video / more — **sin logo**.
- Aviso centrado: candado genérico + `Cifrado E2EE · en este dispositivo`.
- Ticks salientes en navy; reloj = pendiente / relé.
- Composer: campo pill + send circular navy.
- Lista: título grande, búsqueda, filtros `Todos / No leídos / Relé`, tabs Chats · Contactos · Llamadas · Ajustes.

## Tipografía

- **Sans** limpia (web: Manrope; Flutter: system / tema Manrope cuando se empaquete).
- Evitar serif display en producto/marketing principal (el logo es sans).

## Landing

- Hero: marca **Encrypchat** dominante + una frase + CTAs + mockup aprobado (`/product/chat-light.png`).
- Misma paleta light/navy; OG sigue usando logo real (`/og.png` / `/logo.png`).

## Dark

Pendiente. No inventar dark hasta pasar aprobación explícita.
