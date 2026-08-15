# Encrypchat — Design system (aprobado)

**Estado:** UI chat light **aprobada** (2026-08-11). Fuente de verdad visual para landing (`apps/web`), app Flutter (`apps/client`) y materiales de marca.

**Referencias:**

- Chat aprobado: [chat-light-aprobado.png](./chat-light-aprobado.png)
- Lista (orientación): [chats-list-light.png](./chats-list-light.png)
- Logo (colores / isotipo, no en chrome del chat): `encrypchat logo.png` en raíz del monorepo

## Principios

1. **Light por defecto.** Dark se deriva después de los mismos tokens — propuesta medida al final de este documento, **sin aprobar**.
2. Logo = **referencia de color y marca**. No poner el escudo en el header del chat (igual que WhatsApp/Telegram).
3. Híbrido **WhatsApp densidad + Telegram chrome limpio**, con estados Encrypchat (P2P / relé / offline).
4. Azul marino serio; sin purple glow, sin verdosos WhatsApp como acento primario.
5. **Copy en español neutro / Colombia-Bogotá** (tuteo: tú / tienes / toca / pídele). Sin voseo rioplatense.

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

**Sin aprobar.** Nada de esto está implementado y no debe usarse en producto ni
en marketing hasta que marca lo apruebe explícitamente. Lo que sigue es una
**propuesta** derivada de los tokens light aprobados, con los contrastes ya
medidos, para que la decisión se tome sobre números y no sobre una captura.

### Cómo se deriva

No es invertir el light. La identidad de Encrypchat está en el navy, así que en
dark **el navy pasa de ser el acento a ser la superficie**: el fondo y las
tarjetas son navy profundo en vez de gris neutro, y el acento sube a un azul
claro de la misma familia. Es el mismo criterio que mantiene la marca
reconocible cuando se apaga la luz.

| Token light | Hex light | Propuesta dark | Hex dark | Razón |
| --- | --- | --- | --- | --- |
| `canvas` | `#F4F6F8` | `canvas` | `#0B1826` | Fondo de página/chat: navy llevado casi a negro |
| `paper` | `#FFFFFF` | `paper` | `#152A42` | Superficies y burbuja entrante |
| `bubble-out` | `#E6ECF4` | `bubble-out` | `#22405F` | Saliente: navy **levantado**, no oscurecido |
| `ink` | `#14233A` | `ink` | `#E8EFF7` | Texto principal, con tinte azul (no blanco puro) |
| `muted` | `#5A6B7D` | `muted` | `#A2B5CA` | Previews, timestamps, subtítulos |
| `navy` | `#0F2744` | `accent` | `#7CB3EE` | Ticks, iconos activos, enlaces |
| `navy` | `#0F2744` | `accent-fill` | `#2E6BB0` | Relleno del botón send / FAB |
| `navy-mid` | `#1A365D` | `accent-mid` | `#5B9BE0` | Hover / acento secundario |
| `p2p` | `#1B7F4E` | `p2p` | `#3DBE86` | Online / P2P |
| `relay` | `#C47B1A` | `relay` | `#E5A84B` | Vía relé |
| `offline` | `#8A94A0` | `offline` | `#8497A9` | Sin conexión |
| `hairline` | navy @ 12% | `hairline` | `#FFFFFF` @ 12% | Divisores |

Avisos (hoy literales sueltos en `apps/client`, no tokens):

| Uso | Light | Dark propuesto |
| --- | --- | --- |
| Aviso ámbar (texto / fondo) | `#8A5A00` / `#FFF4E5` | `#F0C36D` / `#33270F` |
| Alerta roja (texto / fondo) | `#8C1C13` / `#FDECEA` | `#FF9A8D` / `#3A1512` |

### Lo que obliga a partir un token en dos

En light, `navy` hace dos trabajos: es el relleno del botón send (con texto
blanco encima) y es el color de los ticks **sobre la burbuja saliente**. En dark
esos dos trabajos se separan, porque tiran en direcciones opuestas: un color lo
bastante oscuro para llevar texto claro encima queda por debajo de AA cuando se
dibuja **sobre** la burbuja saliente, y uno lo bastante claro para leerse ahí no
puede llevar texto claro encima. De ahí `accent` y `accent-fill`.

Ese es también el punto donde estas paletas se rompen en la práctica: la burbuja
saliente es el fondo más claro del dark y el más exigente. Está medida abajo.

### Contraste (WCAG 2.1, medido)

AA para texto normal es 4.5:1; 3:1 para componentes de UI y bordes.

| Par | Ratio | |
| --- | --- | --- |
| `ink` sobre `canvas` | 15.45 | AA |
| `ink` sobre `paper` | 12.57 | AA |
| `ink` sobre `bubble-out` | 9.21 | AA |
| `muted` sobre `canvas` | 8.52 | AA |
| `muted` sobre `paper` | 6.94 | AA |
| `muted` sobre `bubble-out` | 5.08 | AA |
| `accent` sobre `canvas` | 8.13 | AA |
| `accent` sobre `paper` | 6.62 | AA |
| **`accent` sobre `bubble-out`** | **4.85** | AA (el más justo) |
| `ink` sobre `accent-fill` | 4.71 | AA |
| `accent-fill` sobre `canvas` | 3.28 | AA (componente) |
| `p2p` / `relay` / `offline` sobre `paper` | 6.18 / 6.96 / 4.84 | AA |
| `p2p` / `relay` / `offline` sobre `canvas` | 7.60 / 8.56 / 5.95 | AA |
| aviso ámbar sobre su fondo | 8.85 | AA |
| alerta roja sobre su fondo | 7.92 | AA |

Separación entre superficies: `paper` vs `canvas` 1.23:1 y `bubble-out` vs
`paper` 1.36:1. Son bajas a propósito y siguen al light aprobado, donde
`bubble-out` vs `paper` es 1.19:1 — lo que distingue las burbujas es la
alineación, no el contraste, y subirlo rompería la densidad tipo WhatsApp.

**Hallazgo sobre el light aprobado (no tocado):** medido igual, `relay` sobre
`paper` da 3.39:1 y `offline` sobre `paper` 3.08:1. Los dos se usan hoy como
texto pequeño (estado del chat, aviso de solicitud P2P), así que están por
debajo de AA para texto. No se cambió nada: es paleta aprobada y la usa la
landing. Queda anotado para que se decida a propósito y no por descuido.

### Por qué no está implementado

Un dark honesto acá no es un mapeo de tokens: es una migración. `apps/client`
resuelve el color en tiempo de compilación — 156 referencias a
`EncrypchatColors` en 15 ficheros, casi todas dentro de widgets `const`, más 16
literales de color fuera del fichero de tokens (los avisos ámbar/rojo). Cambiar
de tema exige que cada una pase a leerse del `Theme` en tiempo de ejecución, lo
que además rompe los `const` de esos widgets. Y hay decisiones que no son de
color y no están tomadas: el QR de *Mi token* necesita fondo claro para que lo
lean los escáneres aunque el resto de la pantalla sea oscuro, la pantalla de
llamada tiene su propio chrome sobre vídeo, y falta definir si el tema sigue al
sistema o se elige en Ajustes (pantalla que hoy no existe).

Se prefirió dejar el light aprobado intacto y traer la paleta medida antes que
entregar medio tema.
