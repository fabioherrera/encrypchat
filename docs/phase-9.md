# Fase 9 — Legal completo y compliance de tiendas

**Estado:** done en lo que depende del repo (2026-08-12); **bloqueado por el operador** para publicar  
**Meta:** privacidad y términos reales y honestos en encrypchat.com, claims alineados con la arquitectura, y expediente de tiendas accionable.

## Entregado

| Pieza | Detalle |
| --- | --- |
| Política de privacidad | `/es/privacy` y `/en/privacy` — 14 secciones con anclas estables; sustituye al stub de F1 |
| Términos de uso | `/es/terms` y `/en/terms` — 13 secciones; sustituye al stub de F1 |
| Render legal | `apps/web/src/components/LegalArticle.tsx` — párrafos y listas tipados, JSON-LD `WebPage` con `dateModified`, nav de enlaces internos |
| Modelo i18n | `LegalDoc` / `LegalSection` en `src/i18n/types.ts`: TypeScript obliga a mantener paridad ES/EN |
| FAQ | 4 preguntas nuevas (qué ve el relay, si las llamadas pasan por servidores, cifrado en el dispositivo, analítica) — también en el JSON-LD `FAQPage` |
| Checklists de tienda | [legal-f9-stores.md](legal-f9-stores.md) — Play, App Store, exportación y copy de ficha |
| Claims corregidos | `AGENTS.md`, `.cursor/rules/encrypchat.mdc`, `roadmap.md` y la landing (detalle abajo) |

## Qué dice ahora la privacidad (y por qué es defendible)

Cada afirmación está contrastada con el código, no con la intención:

| Afirmación pública | Base real |
| --- | --- |
| Clave privada X25519 en el almacén seguro del SO | `identity_service.dart` sobre `flutter_secure_storage` |
| Cuerpos de mensaje y media sellados con AEAD | `local_seal` / `MediaStore` |
| Fichero de base de datos cifrado (SQLCipher), pero legible por quien tenga el dispositivo desbloqueado y acceso al llavero | `local_database.dart` ([audit-f3-storage.md](audit-f3-storage.md)) |
| El directorio `media/` revela cuántos ficheros hay, su tamaño y su fecha (el contenido va sellado) | `media_store.dart` |
| El relay ve `dest_token`, tamaño, timestamps, TTL e IP; nunca plaintext | `services/relay` + [audit-f5-relay.md](audit-f5-relay.md) |
| Remitente forjable en **todas** las rutas: relay y P2P directo | F-1 y F-7 de [audit-f10.md](audit-f10.md). La política lo declara sin acotarlo al relay y avisa también en la sección de llamadas |
| Llamadas P2P DTLS-SRTP, sin SFU ni media server | [audit-f7-calls.md](audit-f7-calls.md) |
| STUN público de Google ve IP y timing | `call_service.dart` (`stun.l.google.com`, `stun1`) |
| Sin analítica ni publicidad | `pubspec.yaml` sin SDK de métricas; `apps/web/src` sin scripts de terceros |
| Sin backup en la nube | `allowBackup="false"` en el manifest |
| Android no pide permiso de galería; la fototeca solo se pide en iOS | `AndroidManifest.xml` sin `READ_MEDIA_IMAGES`/`READ_EXTERNAL_STORAGE` + `media_picker.dart`; `NSPhotoLibraryUsageDescription` en `Info.plist` |
| Desinstalar borra el historial de forma irreversible; la clave privada solo se va con la app en Android | Sin servidor de contenido ni recuperación de cuenta; el llavero del sistema (Keychain, libsecret, Credential Manager) sobrevive a desinstalar — `/privacy` lo declara por plataforma y `/terms` ya no promete que la identidad desaparezca |
| Foto sin bytes en claro en disco; los metadatos locales viven dentro del fichero cifrado | El temporal del picker se borra tras sellar (móvil); en Linux y Windows no se toca el fichero original del usuario. Desde F10 el fichero de base de datos está cifrado con SQLCipher, y `/privacy` distingue esa capa de la de los cuerpos sellados y declara lo que el cifrado de fichero no cubre |

## Claims deshonestos corregidos

| Dónde estaba | Qué decía | Qué dice ahora |
| --- | --- | --- |
| `AGENTS.md:35` | "DB local: SQLCipher" como hecho | SQLite con cuerpos AEAD; SQLCipher **pendiente F10**, con los metadatos legibles enumerados |
| `.cursor/rules/encrypchat.mdc` (stack) | "SQLCipher / almacenamiento cifrado en dispositivo" | Igual que arriba + prohibición explícita de afirmar SQLCipher en copy |
| `docs/roadmap.md` (mermaid + alcance F3) | Nodo `DB[SQLCipher]` y "SQLCipher (o equivalente)" | `DB[SQLite_local_AEAD]` y el estado real entregado |
| `/privacy` (F1) | Stub de 5 párrafos que solo hablaba de intenciones | Política completa: qué existe, dónde vive, qué ven relay y STUN, permisos, retención, derechos, limitaciones |
| `/privacy` contacto | `privacy@encrypchat.com` anunciado sin buzón activo (hallazgo Medium de [legal-f1-landing.md](legal-f1-landing.md)) | Retirado; se declara que no hay canal de contacto y queda como pendiente del operador |
| `/terms` (F1) | Stub de 4 párrafos | Términos completos con estado pre-1.0, sin recuperación de claves, propiedad intelectual, exportación y limitación de responsabilidad |

**Actualización 2026-08-12 (F10).** Las tres primeras filas describen el estado de F9. Con el cifrado de fichero entregado en F10, `AGENTS.md`, `.cursor/rules/encrypchat.mdc` y el copy público ya pueden afirmar **SQLCipher**, siempre con su alcance real: protege el fichero leído del disco, no un dispositivo desbloqueado con el llavero accesible, y no cubre el listado del directorio `media/`. La prohibición de la palabra queda levantada — ver [legal-f9-stores.md](legal-f9-stores.md). En sentido contrario, el párrafo que acotaba el remitente sin autenticar "a la ruta de relay" se reescribió para cubrir las dos rutas (F-7 de [audit-f10.md](audit-f10.md)).

Verificado además que **no** aparece en ninguna superficie pública: "zero metadata", "imposible de hackear", "100 % privado", "zero-knowledge" ni "nada sale de tu dispositivo". La landing ya no promete descargas inexistentes (corregido en F8) y el sitio no carga analítica.

`docs/roadmap.md:316` ("F5–F7 diferidos a propósito") ya estaba corregido por el agente de F8 antes de esta pasada: el texto actual describe el corte de empaquetado y marca Windows/iOS como gaps. Solo se refrescó la línea de "Siguiente paso" de la cabecera para apuntar a F9.

## SEO de las páginas nuevas

- Canonical absoluto por locale (`https://encrypchat.com/es/privacy`, `/en/privacy`, ídem terms) con `hreflang` ES/EN y `x-default`.
- Ya estaban en `sitemap.xml` vía `APP_PATHS`; `robots.txt` no bloquea nada indexable.
- Titles más específicos: "Política de privacidad" y "Términos de uso" en lugar de "Privacidad"/"Términos"; descriptions reescritas al intent real (qué datos existen, quién los ve).
- JSON-LD `WebPage` con `dateModified`, `inLanguage`, `isPartOf` y `publisher` — sin ratings ni datos inventados.
- Enlaces internos: footer → legales; cada página legal → la otra + FAQ + descargas.
- Anclas por sección (`#relay`, `#llamadas`, `#permisos`…) para poder citarlas desde una ficha de tienda o una respuesta AEO.
- Sin JS extra: las páginas siguen siendo estáticas y comparten el mismo bundle.

## DoD

- [x] Privacy y ToS completos, honestos y sin stub, en ES y EN
- [x] Sin datos de contacto o entidad inventados: los huecos están marcados como pendientes
- [x] Claims revisados en `apps/web`, `AGENTS.md`, `docs/` y `.cursor/rules`
- [x] Páginas legales enlazadas desde el sitio, en el sitemap y con metadata/canonical/JSON-LD
- [x] Checklists Play + App Store con dueño por ítem ([legal-f9-stores.md](legal-f9-stores.md))
- [x] `make check-web` verde
- [x] Enlaces legales **dentro de la app** — Mi token → Acerca de (y pie con Privacidad / Términos); locale ES/EN según el idioma del dispositivo
- [x] Reporte y bloqueo de usuarios para cumplir política de UGC — bloqueo local que corta chat, media y llamadas; informe de abuso local ([legal-f9-stores.md](legal-f9-stores.md#reporte-y-bloqueo-de-usuarios))
- [x] `NSPhotoLibraryUsageDescription` en `ios/Runner/Info.plist`
- [x] Android sin permiso de galería — Photo Picker del sistema ([legal-f9-stores.md](legal-f9-stores.md#fotos-sin-permiso-de-galería-android))
- [ ] Revisión por abogado — operador
- [ ] Entidad legal, jurisdicción y buzón de contacto — operador
- [ ] Firma release y cuentas de desarrollador — operador ([phase-8.md](phase-8.md))

## Gaps honestos

| Ítem | Nota |
| --- | --- |
| Sin revisión de abogado | Los documentos lo dicen en su propio encabezado |
| Sin entidad legal ni jurisdicción | Bloquea el cierre de privacidad y términos; no se inventó ninguna |
| Sin buzón de contacto | El correo del stub se retiró en lugar de mantener una dirección muerta |
| Sitio no live | `https://encrypchat.com` sigue pendiente de DNS y token de Cloudflare (F1); las tiendas exigen URL accesible |
| Enlaces legales a un sitio que aún no responde | La app abre `https://encrypchat.com/{es,en}/{privacy,terms}` en el navegador del sistema; hasta que el sitio esté live esas URLs dan 404. Si no hay navegador (desktop restringido) la app copia el enlace en vez de fallar |
| Bloqueo por identidad declarada | Dos capas: el core rechaza al par tras el handshake y el cliente descarta por el token que declara el frame. **Corrección (0.8.0):** hasta EH02 la identidad del handshake no estaba probada (F-1), así que esa primera capa filtraba por un valor que el atacante elegía; ahora sí. Lo que sigue sin arreglar: el fix de remitente en relay (`ECS1`) y EH02 no están en vigor hasta que el cliente se cablee, y cualquiera puede crear un token nuevo. Documentado en el propio copy de la app |
| Reporte sin destinatario | Es un informe local: no hay servidor que lo reciba y no incluye el contenido de la conversación. Si una tienda exige un canal humano, hace falta el buzón del operador |
| Photo Picker en Android antiguo sin Play Services | Se cae a `ACTION_OPEN_DOCUMENT`: se puede adjuntar la foto, pero con el explorador de documentos en vez de la cuadrícula de galería. Verificado leyendo `image_picker_android` y `androidx.activity`, no en hardware ([legal-f9-stores.md](legal-f9-stores.md#fotos-sin-permiso-de-galería-android)) |
| ~~Privacidad web desalineada~~ | Corregido: `/privacy` ya no lista `READ_MEDIA_IMAGES` ni `READ_EXTERNAL_STORAGE`, describe el Photo Picker (con la caída a explorador de ficheros) y añade la fototeca de iOS. Reconciliado contra `AndroidManifest.xml` e `Info.plist` en ES y EN, más una FAQ nueva sobre acceso a fotos |
| ~~Copia temporal del picker~~ | Cerrado en código: `_pickAndSendImage` borra en un `finally` la copia que el picker deja en la caché privada (Android e iOS), y al arrancar se barren los restos de sesiones anteriores — incluida la copia a tamaño completo que Android hace antes de reescalar y que el plugin nunca elimina. En Linux y Windows no se borra nada porque ahí el picker devuelve el fichero original del usuario. Verificado con tests sobre la política de borrado; falta comprobación en dispositivo ([phase-6.md](phase-6.md)) |
| Identidad que sobrevive a desinstalar (Linux, Windows, iOS) | La clave vive en el llavero del sistema: libsecret en Linux, Credential Manager en Windows, Keychain en iOS. Ninguno se limpia al borrar la app — solo Android (EncryptedSharedPreferences en el directorio de la app) cumple lo que dice la política. La salida es una acción de "borrar identidad y datos" en la app; evaluada y **no implementada** todavía porque obliga a rehacer el ciclo de vida de la sesión (ver nota abajo) |
| `ITSAppUsesNonExemptEncryption` sin declarar | Decisión de exportación pendiente de abogado |
| APK con keystore de debug | Bloquea Play por sí solo ([phase-8.md](phase-8.md)) |
| Traducción legal | ES y EN se escribieron en paralelo, no traducidos por profesional; si se publica en una jurisdicción concreta, revisar el idioma que sea vinculante |

## Borrar identidad desde la app — evaluado, pendiente de diseño

Único remedio en nuestras manos para el gap de desinstalación en Linux, Windows e iOS. Lo que
haría falta, comprobado sobre el código actual:

| Pieza | Estado |
| --- | --- |
| `IdentityService.wipe()` — borra `identity_secret_v1` y `identity_token_v1`, y pone a cero la copia en memoria | ya existe |
| `LocalDatabase` — cerrar, borrar el fichero `encrypchat_v1.db` y la clave `local_db_key_v1` del llavero | falta (la ruta se calcula dentro de `open()`, hay que extraerla) |
| `MediaStore` — borrar `support/media/` entero | falta |
| `relay_base_url_v1` del llavero | falta |
| `SessionController` — parar nodo y timers, disponer `MessagingService` y `CallService`, anularlos y volver a `needsOnboarding` | falta, y es la parte cara |

El bloqueo no es el borrado, es el ciclo de vida: hoy `_messaging` y `_calls` se crean una sola vez
en `_enterReady` y solo se disponen al morir el controlador. La acción saldría de **Acerca de**, que
está apilada sobre `ShellPage`; al pasar a `needsOnboarding` el `home` cambia, pero las rutas
apiladas siguen vivas y cualquier reconstrucción de `ShellPage` o `ChatsPage` llamaría al getter
`session.messaging` ya anulado (`StateError` en pantalla). Habría que vaciar la pila de navegación,
tolerar la transición `ready → needsOnboarding` en cada pantalla y cortar una llamada en curso.

Es un cambio de ciclo de vida con su propio diseño y sus propios tests, no un botón. Se deja fuera a
propósito: una función destructiva a medias es peor que el gap documentado.

## Verificar

```bash
make check-web
# Revisar: /es/privacy, /en/privacy, /es/terms, /en/terms, /es/faq
```
