# Auditoría de salud — Encrypchat (readonly, 2026-08-12)

Alcance: todo el código propio (Dart, Rust, TS). Pregunta de origen: ¿el código está
liviano, sin basura, seguro y estable?

## Veredicto

**LIMPIO CON NOTAS.**

El código **no está pesado ni tiene basura estructural**: ~10.200 líneas propias, 248
ficheros versionados (3,4 MiB en git), cero archivos huérfanos, cero TODOs, cero
secretos, ningún `unwrap()`/`expect()` en rutas alcanzables por red. Los 11 GB del
directorio son `target/`, `apps/client/build/` y `.tools/`, todos gitignored.

Lo que sí hay son **2 hallazgos Alta nuevos** de endurecimiento (no cubiertos por
`audit-f5/f6/f7`) y varias asperezas de robustez.

## Métricas

| Área | Líneas |
| --- | --- |
| `apps/client/lib` (Dart) | 4.678 |
| `apps/client/test` (Dart) | 157 (9 casos) |
| `crates/core` (Rust) | 2.567 |
| `services/relay` (Rust) | 758 |
| `apps/web/src` (TS/TSX) | 2.083 |
| **Total propio** | **~10.243** |

| Tamaño | Valor |
| --- | --- |
| Ficheros versionados | 248 |
| Repo git (pack) | 3,38 MiB (~2,7 MB son PNGs duplicados) |
| Directorio en disco | 11 GB (todo gitignored salvo lo anterior) |
| Deps | Flutter 13+2 · core 10 · relay 12+3 |
| Tests | 35 Rust + 9 Dart |

`dist/*.apk` y `dist/*.tar.gz` ya están ignorados (`.gitignore:70`). Sin binarios,
logs ni cachés versionados por error.

## Hallazgos

| Sev | Ubicación | Problema | Fix |
| --- | --- | --- | --- |
| **Alta** | `messaging_service.dart:476-485` | La política "llamadas solo P2P" se aplica al enviar pero **no al recibir**: el inbound de relay acepta `kind == 'call'`. Un contacto puede suplantar a otro y obtener micro/cámara si aceptás | Descartar `kind == 'call'` en `_handleRelayBlob` |
| **Alta** | `net.rs:437-452,756-772` | Handshake EH01 sin timeout ni límite de conexiones; `read_proof` reserva hasta 16 MiB **antes** de autenticar → DoS de memoria/fds | Timeout 5 s, semáforo de conexiones sin autenticar, cap pre-auth ~4 KiB |
| Media | `net.rs:564` + `:126` | `try_send` descarta el frame si el canal está lleno pero igual manda ACK → `delivered` miente | No ACKear si `try_send` falla |
| Media | `messaging_service.dart:453,528`; `call_service.dart:178` | `debugPrint('$e')` con `FormatException` incluye fragmento del source = plaintext descifrado o SDP; `debugPrint` no se elimina en release | Loguear `e.runtimeType` o un código |
| Media | `api.rs:131-137,180-184` | El relay loguea `dest_token` completo + bytes + TTL = el metadato que el relay ciego promete no retener | Truncar/hashear o no loguear |
| Media | `api.rs:108`, `store.rs:83` | `enqueue` sin cuota por destino → llenado de disco | Cuota por `dest_token` + rate-limit por IP |
| Media | `messaging_service.dart:56,146-172` | `_cache` sin límite retiene plaintext y `mediaBytes` completos; nunca se poda | Paginar y leer media on-demand |
| Media | `messaging_service.dart:101-108` | Timers de 400 ms / 8 s sin guarda de reentrada | Flag `_draining`/`_pulling` |
| Media | `media_envelope.dart:58-73` | `sublist` antes de validar longitudes → `RangeError` aborta el `while` de `_drainInbound` | Validar antes de cortar |
| Media-Baja | `relay_client.dart:16-19` | `http://` sin aviso: `dest_token`, pubkey y proof en claro | Exigir `https` o warning en UI |
| Baja | `media_envelope.dart:31-32,60,64` | `codeUnits` en vez de UTF-8 → nombres corruptos | `utf8.encode`/`decode` |
| Baja | `messaging_service.dart:462-472` | Rama muerta: EM01 crudo por relay crea conversación `unknown` | Eliminar o rechazar |
| Baja | `call_service.dart:423-428` | `Future.delayed` no cancelable llama `notifyListeners()` tras `dispose` | Guardar timer y cancelar |
| Baja | `call_service.dart:350-363,402-406` | Callbacks de `_pc` no desconectados antes de `close()`; posible reentrada en `_reset` | Anular callbacks + guarda |
| Baja | `chat_page.dart:377,435-436` | 3 `TextEditingController` sin `dispose` | Disponer en `whenComplete` |
| Baja | `local_database.dart:139` | `catch (_) {}` en migración v1→v2 y luego `DROP TABLE` | No dropear si la copia falló |
| Baja | `messaging_service.dart:160` | `catch (_) {}` enmascara fallo de `local_open` | Distinguir "sin caption" de fallo |
| Baja (docs) | `AGENTS.md:35`, `.cursor/rules/encrypchat.mdc` | "SQLCipher" sin marcar como pendiente; el SQLite está en claro salvo los bodies | Añadir "(pendiente F10)" |
| Baja (docs) | `docs/roadmap.md:316` | Dice "F5–F7 diferidos" cuando ya están done | Reescribir (se refiere al corte de packaging) |

## Estado de remediación (2026-08-12, `/backend`)

| Hallazgo | Estado | Cómo |
| --- | --- | --- |
| **Alta** — inbound de relay acepta `kind == 'call'` | **cerrado** | `_handleRelayBlob` descarta la rama (log sin datos). La rama de envío por relay de `sendCallSignal` y el parámetro `allowRelay` se eliminaron: una sola política P2P-only en ambos sentidos |
| **Alta** — handshake EH01 sin timeout/límites | **cerrado** | `HANDSHAKE_TIMEOUT` 5 s en accept y en los dos dials, semáforo de 32 handshakes sin autenticar, `MAX_PREAUTH_LEN` 4 KiB en offer/proof. Frame de datos post-handshake sigue en 16 MiB. 3 tests nuevos en `net::tests` |
| Media — ACK con `try_send` descartado | **cerrado** | Sin ACK si el canal inbound está lleno; el emisor no marca `delivered` |
| Media — `debugPrint('$e')` filtra plaintext | **cerrado** | `messaging_service` (3), `call_service` (2), `session_controller` (2) loguean `e.runtimeType`. `native_library.dart` se deja: solo error de carga de `.so`/`.dll`, sin contenido |
| Media — relay loguea `dest_token` | **cerrado** | Campo `dest` eliminado de `enqueue`/`pull`; política de logs documentada en `services/relay/README.md` |
| Media — `sublist` antes de validar en EM01 | **cerrado** | `decode` valida caps y rango contra `bytes.length` antes de cortar; 6 tests nuevos. `_drainInbound` y el bucle de `pullFromRelay` descartan el frame/blob inválido y siguen |
| Baja — `cupertino_icons`, `_replaceCache`, meta `db_key_fingerprint` | **cerrado** | Eliminados. Quitar la meta no toca el esquema (sigue `version: 3`): las DBs existentes conservan la fila, inerte |
| Baja (docs) — SQLCipher pendiente, `roadmap.md:316` | abierto | `AGENTS.md` / `roadmap.md` los tiene otro agente (F8) |
| PNGs duplicados | abierto por diseño | Tocan `apps/web`; requieren pase `/seo` antes de borrar |

Límite conocido del semáforo: 32 conexiones sin autenticar y sostenidas retrasan un dial
legítimo hasta 5 s (sin cuota por IP en el puerto P2P). Es una degradación acotada, no un OOM.

### Segunda tanda (2026-08-12, `/backend`)

| Hallazgo | Estado | Cómo |
| --- | --- | --- |
| Media — `enqueue` sin cuota por destino | **cerrado** | 200 blobs / 8 MiB pendientes por `dest_token`, contados bajo el mismo lock que el insert → `507` opaco (sin contadores ni límites en la respuesta). Vaciar el buzón libera cuota |
| Media — sin rate-limit por IP; P0 de challenges de F5 | **cerrado** | Token bucket en memoria por IP y por endpoint: 60/min `enqueue`, 30/min `challenge` y `pull` → `429`. Todo configurable con `ENCRYPCHAT_RELAY_MAX_MSGS/MAX_BYTES/ENQUEUE_RPM/CHALLENGE_RPM` |
| Media — `_cache` sin límite retiene plaintext y `mediaBytes` | **cerrado** | `mediaBytes` desapareció de `ChatMessage`: la UI pide los bytes con `mediaBytesFor` y los guarda solo mientras la burbuja está en pantalla. Caché de 200 mensajes por conversación y 3 conversaciones (LRU); `_pushCache` ya no siembra conversaciones frías |
| Media — timers sin guarda de reentrada | **cerrado** | Flags `_draining` / `_pulling` liberados en `finally` |
| Media-Baja — `http://` sin aviso | **cerrado** | No se bloquea (las demos LAN lo necesitan): `RelayInsecureNotice` persistente en la lista de chats mientras el relay esté sin TLS, más aviso en vivo en el diálogo ☁ al teclear una URL sin `https` |
| Baja — `codeUnits` en EM01 | **cerrado** | `utf8.encode`/`utf8.decode` para mime y name; los caps siguen midiendo bytes y `encode` rechaza nombres que se pasen en UTF-8. 2 tests (tildes + emoji no-BMP) |
| Baja — rama `unknown` de relay | **cerrado** | Un EM01 crudo por relay ya no crea conversación: se rechaza como `FormatException` (no trae remitente) |
| Baja — `Future.delayed` no cancelable en `call_service` | **cerrado** | `Timer` guardado y cancelado en `dispose`, más flag `_disposed` y `_notify()` que no notifica tras `dispose` |
| Baja — callbacks de `_pc` sin desconectar | **cerrado** | `onIceCandidate` / `onConnectionState` / `onTrack` a `null` antes de `close()`, más guarda `_resetting` contra la reentrada desde `onConnectionState` |
| Baja — 3 `TextEditingController` sin `dispose` | **cerrado** | `whenComplete` en los dos diálogos de `chat_page.dart` |
| Baja — `catch (_) {}` + `DROP TABLE` en migración v1→v2 | **cerrado** | `messages_old` solo se dropea si la copia funcionó; el fallo se loguea por código |
| Baja — `errorMessage = e.toString()` en bootstrap | **cerrado** | Mensaje genérico + `runtimeType`; el detalle no llega ni a pantalla ni a log |
| Baja — `catch (_) {}` al abrir el caption | **cerrado** | `_openCaption` distingue "sin caption" (`null` → se muestra el mime) de fallo de `local_open` (etiqueta propia + `status: error`) |

Gap de UX que introduce el límite del caché: la conversación abierta muestra los últimos
200 mensajes; el historial anterior sigue en la DB pero todavía no hay paginación en la UI
(pedirla a `/frontend` cuando haga falta).

Ya auditado y aceptado antes (no cuenta como nuevo): `from` forjado en relay (`audit-f5`),
challenge overwrite, delete-before-ack, HTTP por defecto, sin FLAG_SECURE, STUN público,
SQLCipher diferido a F10.

## Basura a borrar

| Riesgo | Qué |
| --- | --- |
| Seguro | `encrypchat logo.png` (raíz, 1,2 MB) — idéntico a `apps/web/public/logo.png` |
| Seguro | `apps/web/public/logo.png` (1,2 MB) — sin referencias en `apps/web/src` |
| Seguro | `docs/design/chat-light-aprobado.png` (1,5 MB) — idéntico a `apps/web/public/product/chat-light.png` |
| Seguro | `cupertino_icons` en `pubspec.yaml` — cero imports |
| Seguro | `_replaceCache` (`messaging_service.dart:617`) — alias literal de `_pushCache` |
| Seguro | Meta `db_key_fingerprint` (`local_database.dart:116-119`) — se escribe, nunca se lee |
| Verificar | Triplicación `sendText`/`sendMedia`/`sendCallSignal` (~200 líneas) — extraer `_sendFrameOrRelay()`; ruta crítica, requiere tests |
| Verificar | Generador de id duplicado ×3 (16 vs 12 bytes) |
| Verificar | `_hexToBytes` duplicado ×2 (uno valida entrada externa) |
| No borrar | `dist/*` — entregables en prueba, ya ignorados |

Los PNG duplicados tocan `apps/web` → requieren pase `/seo` antes de borrar.

## Qué no tocar

- `target/`, `apps/client/build/`, `.tools/` — 99 % del peso, ignorados, en uso por builds.
- `inject_peer` / `connect_multiaddr` (`net.rs:207-237`) — `connect_multiaddr` es la ruta real de dial manual.
- Doble verificación token↔pubkey en el relay — defensa en capas, no redundancia.
- `expect("32-byte key")` (`crypto.rs:71,110`) — inalcanzable por construcción.
- `zeroize`, `hex`, `ffi`, `sqflite_common_ffi` — todas en uso.
- Timer de 400 ms de `_drainInbound` — el FFI expone `try_recv` no bloqueante.
- `catch (_) {}` en `hangup`/`rejectIncoming` — best-effort intencional.
- `docs/audit-f*.md` — traza de auditoría por fase.

## Top 5 acciones (valor/riesgo)

1. Cerrar la señalización de llamadas por relay en el inbound (`messaging_service.dart:476`).
2. Endurecer el handshake en `net.rs` (timeout, cap de conexiones, buffer pre-auth).
3. Dejar de interpolar excepciones en logs (5 `debugPrint` + 2 `tracing::info!`).
4. No ACKear cuando el canal inbound está lleno (`net.rs:564`).
5. Limpieza sin riesgo: PNGs duplicados, `cupertino_icons`, `_replaceCache`, fingerprint muerto.

## Estado de release

- **Demo / LAN entre contactos de confianza:** aceptable (corte declarado en `pre-f7-readiness.md`).
- **Relay público:** sigue sin ser release-ready. Ya están las cuotas, el rate-limit por IP
  y el aviso de falta de TLS, pero el bloqueante real es el `from` forjado de F5 para
  mensajes y media; falta también TLS obligatorio (hoy es responsabilidad del operador).
- El hallazgo 2 (DoS de handshake) está cerrado; el escenario LAN ya no expone
  reserva de memoria pre-autenticación.

## Cobertura de tests — gap principal

Sin ningún test: `messaging_service.dart` (653 líneas), `call_service.dart` (445),
`local_database.dart` (281), `media_store.dart`, `relay_client.dart`. Los 9 tests Dart
cubren códecs, export de contactos y dos widgets. Rust está mucho mejor (35 tests,
incluidos los negativos de handshake y PoP).
