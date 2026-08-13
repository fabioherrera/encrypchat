# Compliance de tiendas — Fase 9 (Google Play / App Store)

**Fecha:** 2026-08-12  
**Alcance:** requisitos de publicación de la app Flutter (`apps/client`) en Google Play y App Store, con el estado real del repo hoy.  
**No es asesoría legal.** Ningún abogado ha revisado este expediente. Antes de enviar a revisión hace falta un pase de abogado sobre privacidad, términos, clasificación por edad y control de exportación.

Permisos de micro/cámara y frases que **no** se pueden afirmar: [legal-f7-calls.md](legal-f7-calls.md).  
Estado de empaquetado y firma: [phase-8.md](phase-8.md).  
Limitaciones reales del producto: [audit-f5-relay.md](audit-f5-relay.md) · [audit-f6-media.md](audit-f6-media.md) · [audit-f7-calls.md](audit-f7-calls.md) · [audit-f3-storage.md](audit-f3-storage.md).

## Semáforo

| # | Bloqueante | Tienda | Dueño |
| --- | --- | --- | --- |
| 1 | APK firmado con **keystore de debug**; Play exige AAB firmado con clave de release | Play | Operador |
| 2 | Sin build iOS: `crates/core` no está enlazado (requiere macOS) | App Store | Operador (host Mac) |
| 3 | Sin cuenta de desarrollador (Play 25 USD única / Apple 99 USD anual) ni verificación de identidad | Ambas | Operador |
| 4 | Sin entidad legal, domicilio, jurisdicción ni buzón de contacto → la política de privacidad no puede cerrarse | Ambas | Operador |
| 5 | ~~`https://encrypchat.com` todavía no está live~~ → **hecho** (Dokploy + Cloudflare Tunnel, 2026-08-13): las páginas legales ya son accesibles | Ambas | Operador ✅ |
| 6 | ~~Sin mecanismos de **reporte y bloqueo** de usuarios~~ → **hecho** (bloqueo local que corta chat, media y llamadas + informe local de abuso) | Ambas | `/frontend` ✅ |
| 7 | ~~La app no enlaza privacidad ni términos desde su propia UI~~ → **hecho** (Mi token → Acerca de) | Ambas | `/frontend` ✅ |
| 8 | Sin revisión de abogado | Ambas | Operador |

Nada de esto se resuelve escribiendo texto: 1–5 y 8 son decisiones del operador. 6–7 eran código de cliente y ya están implementados ([Reporte y bloqueo](#reporte-y-bloqueo-de-usuarios)).

## Listo en el repo

| Ítem | Dónde |
| --- | --- |
| Política de privacidad completa y honesta (ES/EN) | `/es/privacy`, `/en/privacy` |
| Términos de uso completos (ES/EN) | `/es/terms`, `/en/terms` |
| Enlace desde el footer del sitio, sitemap y hreflang | `apps/web` |
| Purpose strings iOS de micro y cámara | `apps/client/ios/Runner/Info.plist` |
| Permisos Android acotados a la llamada — **sin permiso de galería** (Photo Picker del sistema) | `AndroidManifest.xml`, `lib/core/media_picker.dart` |
| Backup automático de Android desactivado (`allowBackup="false"`) | `AndroidManifest.xml` |
| Sin analítica, sin publicidad, sin identificadores de anuncios | verificado en `apps/web/src` y en `pubspec.yaml` |
| `key.properties` opcional para firma release sin romper el build | [phase-8.md](phase-8.md); `key.properties`, `*.jks` y `*.keystore` gitignored |
| Purpose string iOS de fototeca | `NSPhotoLibraryUsageDescription` en `ios/Runner/Info.plist` |
| Bloqueo de usuarios (chat + media + llamadas) con persistencia | `local_database.dart` (tabla `blocked`), `messaging_service.dart`, `call_service.dart` |
| Reporte de abuso local | `models/abuse_report.dart`, `screens/safety_actions.dart` |
| Enlaces a privacidad y términos dentro de la app | `screens/about_page.dart` + pie de `my_token_page.dart` |

## Google Play

### Cuenta y artefacto

- [ ] Cuenta de desarrollador con verificación de identidad (y D-U-N-S si se publica como organización) — **operador**
- [ ] Artefacto **AAB** firmado con clave de release y Play App Signing. Hoy `dist/` produce un APK firmado con la keystore de **debug**: sirve para sideload, Play lo rechaza — [phase-8.md](phase-8.md)
- [ ] `applicationId` definitivo (`com.encrypchat.encrypchat`) reservado en la consola
- [ ] `targetSdk` al nivel exigido por Play en la fecha de envío (hoy hereda el default de Flutter; verificar antes de subir)

### Data safety (formulario)

Declaración propuesta, coherente con lo que hace el código:

| Sección | Respuesta | Justificación |
| --- | --- | --- |
| ¿Recopila o comparte datos de usuario? | **No** para todas las categorías | No hay cuenta, backend de contenido, analítica ni SDK de terceros que exfiltre |
| Mensajes / fotos | No recopilados | E2EE en origen; se guardan en el dispositivo; el relay solo ve el sobre cifrado |
| Contactos | No recopilados | No se lee la agenda del teléfono; los contactos son tokens introducidos a mano o por QR |
| Identificadores / publicidad | No | Sin advertising ID, sin atribución |
| Diagnóstico / crash logs | No | Sin crash reporting ni telemetría |
| Ubicación | No | No se pide ningún permiso de ubicación |
| ¿Datos cifrados en tránsito? | **Sí** | E2EE en origen + DTLS-SRTP en llamadas |
| ¿El usuario puede pedir el borrado? | **Sí, en el dispositivo** | No hay cuenta que borrar; desinstalar elimina identidad e historial |

Matices que deben ir en la ficha, no ocultarse:

- Si el usuario configura un relay, ese servicio procesa el sobre cifrado, el token de destino, el tamaño, los tiempos y la IP de conexión.
- Las llamadas usan STUN público de Google: ve IP y momento de la llamada.
- Play interpreta "recopilar" como envío fuera del dispositivo a un servidor **del desarrollador**. El relay puede ser de terceros y es opcional; declararlo como funcionalidad y describirlo en la privacidad, no como recopilación propia. **Confirmar esta lectura con abogado.**

### Permisos y políticas

- [ ] Justificación de `RECORD_AUDIO` y `CAMERA`: solo durante una llamada en curso, a petición del usuario
- [x] **Photo and Video Permissions declaration**: **no aplica**. La app migró al Android Photo Picker y ya no declara `READ_MEDIA_IMAGES` ni `READ_EXTERNAL_STORAGE`, así que no hay acceso amplio a fotos que justificar — ver [Fotos sin permiso de galería](#fotos-sin-permiso-de-galería-android)
- [x] Política de contenido generado por usuarios: reporte y bloqueo implementados en la app — ver [Reporte y bloqueo](#reporte-y-bloqueo-de-usuarios). En la ficha hay que describirlos tal como son: bloqueo real en el dispositivo, informe **local** (no hay moderación de contenido porque es E2EE)
- [ ] Sección de eliminación de cuenta: declarar "la app no crea cuentas" y apuntar al borrado local
- [ ] Declaración de anuncios: **no contiene anuncios**
- [ ] Público objetivo: 13+; no marcar Familias/Diseñado para niños
- [ ] Clasificación IARC: cuestionario con comunicación de usuarios sin moderar → esperar Teen / PEGI 12 aprox.
- [ ] URL de política de privacidad: `https://encrypchat.com/es/privacy` y `https://encrypchat.com/en/privacy` (requiere el sitio live, bloqueante 5)
- [ ] Instrucciones de revisión: el chat es P2P y necesita **dos dispositivos**; sin ellas el revisor no puede probar la app. Incluir guion corto con intercambio de token por QR

## App Store (Apple)

### Cuenta y artefacto

- [ ] Apple Developer Program activo — **operador**
- [ ] Build iOS real: hoy falta compilar `crates/core` para `aarch64-apple-ios` y enlazarlo con `-force_load`; sin eso la app arranca y muere al cargar el FFI — [phase-8.md](phase-8.md)
- [ ] `IPHONEOS_DEPLOYMENT_TARGET = 13.0` ya coincide con lo que exige `flutter_webrtc`

### App Privacy (nutrition labels)

Declaración propuesta: **Data Not Collected** en todas las categorías.

Condiciones para que esa declaración sea cierta y sostenible:

- Ningún SDK de terceros incorporado recopila datos en nombre del desarrollador (verificado hoy: sin analítica, sin publicidad, sin crash reporting).
- El relay es infraestructura opcional elegida por la persona usuaria y solo procesa cifrado; se describe en la política de privacidad.
- STUN público de Google es un ayudante de conectividad, no un recolector de datos en nuestro nombre.
- **Confirmar con abogado** antes de firmar el formulario: Apple pregunta también por datos que recopilen "third-party partners", y la lectura de relay + STUN debe quedar documentada por escrito.

### Purpose strings

Ya presentes en `Info.plist` (texto exacto, en inglés, en el fichero):

| Clave | Estado |
| --- | --- |
| `NSMicrophoneUsageDescription` | Presente — llamadas cifradas P2P; dice explícitamente que el audio no se sube a servidores de Encrypchat |
| `NSCameraUsageDescription` | Presente — escanear el QR de un contacto y videollamadas cifradas P2P; dice que los fotogramas se procesan en el dispositivo |
| `NSPhotoLibraryUsageDescription` | **Presente** — acceso solo al elegir una foto para un chat; dice que la foto se cifra en el dispositivo y no se sube a servidores de Encrypchat |

Frases prohibidas en purpose strings y en la ficha (ver [legal-f7-calls.md](legal-f7-calls.md)): "cero metadatos", "el contenido nunca sale del dispositivo" (los paquetes van al par), "imposible de interceptar", "zero-knowledge".

### Políticas de revisión

- [x] **Guideline 1.2 (contenido generado por usuarios)**: reporte y bloqueo implementados ([detalle](#reporte-y-bloqueo-de-usuarios)). Queda del lado del operador el cuarto requisito: **datos de contacto publicados** para que un usuario pueda escalar un abuso (bloqueante 4). Sigue siendo el riesgo de rechazo más probable: Apple puede pedir además filtro de contenido objetable, que el E2EE hace imposible; la respuesta en las notas del revisor debe ser esa, por escrito
- [ ] Guideline 5.1.1: sin cuenta obligatoria (cumple: no hay cuentas)
- [ ] Guideline 5.1.2: sin recopilación oculta (cumple)
- [ ] URL de política de privacidad en App Store Connect **y** enlace accesible dentro de la app (bloqueante 7)
- [ ] Clasificación por edad: cuestionario con comunicación sin moderar entre usuarios; esperar 12+/17+ según respuestas de UGC. Decidir con abogado
- [ ] Notas para el revisor: la app necesita **dos dispositivos** en la misma red para demostrar el chat P2P; adjuntar guion e indicar que no hay credenciales

## Fotos sin permiso de galería (Android)

`main()` llama a `configureMediaPicker()` (`lib/core/media_picker.dart`), que pone
`ImagePickerAndroid.useAndroidPhotoPicker = true` sobre la instancia del plugin. El flag vive en
la implementación de plataforma, así que vale para cualquier llamada al picker que se añada
después, no solo para la del chat. En Linux, Windows e iOS la función no hace nada
(`ImagePickerPlatform.instance` no es la implementación Android).

Con eso, el `AndroidManifest.xml` ya no declara `READ_MEDIA_IMAGES` ni `READ_EXTERNAL_STORAGE`:
el picker devuelve un permiso de lectura sobre **la foto elegida**, no sobre la galería. El
único camino del cliente que toca ficheros del usuario es `_pickAndSendImage` en
`chat_page.dart`; el resto (`local_database.dart`, `media_store.dart`, `native_library.dart`)
trabaja en el almacenamiento privado de la app. `test/media_picker_test.dart` verifica el flag y
que el manifest siga sin esos permisos.

Qué intent se lanza, según el dispositivo (cadena de `androidx.activity` `PickVisualMedia`, la
que usa el plugin):

| Dispositivo | Qué se abre | Permiso |
| --- | --- | --- |
| Android 13+ (o 11/12 con la extensión de SDK) | Photo Picker del sistema | ninguno |
| Android ≤12 con Play Services | Photo Picker backported (módulo que instala Play; el plugin trae el `ModuleDependencies` service que lo pide) | ninguno |
| Android ≤12 **sin** Play Services (AOSP, algunas ROM) | `ACTION_OPEN_DOCUMENT` → gestor de documentos del sistema | ninguno |

**Gap (degradación, no rotura):** en un dispositivo antiguo sin Play Services la persona ve el
explorador de documentos en vez de la cuadrícula de fotos — más pasos, sin previsualización tipo
galería. Sigue pudiendo adjuntar. Solo se quedaría sin poder elegir foto una ROM que no traiga
**ninguna** actividad para `ACTION_OPEN_DOCUMENT` (sin DocumentsUI), y en ese caso el permiso
tampoco lo arreglaría: `image_picker` no consulta `MediaStore` por su cuenta, siempre lanza un
selector. Sin dispositivo físico esto está verificado leyendo el código de
`image_picker_android` 0.8.13+19 y de `PickVisualMedia`, no en hardware.

## Reporte y bloqueo de usuarios

Implementado en `apps/client` (Android, iOS, Linux, Windows: es lógica Dart compartida, sin código por plataforma).

### Bloquear — se cumple de verdad

Tabla `blocked` en la base local (migración v4), indexada por **token**, no por contacto: alguien puede mandar frames sin estar importado como contacto, y borrar el contacto no debe levantar el bloqueo. Se carga en memoria al arrancar la sesión, así que el corte no depende de una consulta por mensaje.

| Camino | Dónde se corta | Qué pasa |
| --- | --- | --- |
| P2P (texto, foto EM01 y señalización de llamada) | `MessagingService.handleInboundFrame`, antes de descifrar | El token del remitente viaja en la cabecera EC04: el frame se descarta sin abrir el ciphertext, sin escribir en la DB y sin llegar a `CallService` |
| Relay ciego | `MessagingService.handleRelayBlob`, tras descifrar (el sobre no expone el remitente antes) | Se descarta; el relay ya lo borró al hacer pull, así que no queda copia |
| Salida | `sendText`, `sendMedia`, `sendCallSignal` | Lanzan antes de tocar el nodo: no se puede escribir ni llamar a un bloqueado |
| Llamada entrante | `CallService._onInboundSignal` y `startCall` | Segunda verificación por si otro transporte entregara señalización: nunca se pide micro/cámara por un bloqueado |

Sobrevive a reinicios (está en disco) y se puede deshacer desde el chat, la ficha del contacto o **Mi token → Acerca de → Contactos bloqueados**.

Límites honestos, que no se deben ocultar en la ficha:

- El bloqueo es por identidad. Quien quiera insistir puede generar un token nuevo; entonces aparece como desconocido y hay que volver a bloquear.
- El remitente de un frame es un dato **declarado**, no autenticado (P0 abierto de F5/F6). Alguien podría forjar otro token para saltarse el bloqueo; se arregla con auth de remitente en el core, no en la UI.
- No se avisa al bloqueado: no hay señal saliente, justamente para no darle información.
- La sesión libp2p no se rechaza en el transporte: el core no expone hoy una lista de denegación. El corte es en la capa de aplicación, antes de descifrar y antes de persistir. Pedirlo a `/backend` si se quiere cerrar también la conexión.

### Reportar — lo que sí se puede prometer

No hay servidor de moderación ni forma de mandar el contenido de otra persona a ningún lado sin romper el zero-cloud. En vez de inventar un endpoint, el flujo es local: la persona elige motivo, escribe qué pasó y la app arma un informe de texto con el token reportado, el suyo, la fecha y el estado de bloqueo, y lo **guarda en un archivo** que ella elige. Decide ella si se lo da a un abogado, a la policía o a otra plataforma donde esa persona también opere.

- El informe **no** incluye mensajes ni fotos: exportar el contenido de otro automáticamente sería mover en claro lo que la app promete no mover. Si alguien necesita aportar pruebas, las adjunta a mano.
- Un archivo y no el portapapeles (F-14 de [audit-f10.md](audit-f10.md)): el informe relaciona la identidad de quien denuncia con la de quien acosa, y el portapapeles lo leen gestores y teclados de terceros y en escritorio se sincroniza a la nube. Copiar sigue estando, como segunda acción y debajo de la frase que dice qué implica — quitarlo dejaba sin salida el caso de pegarlo en un mail desde el teléfono.
- El copy de la app dice literalmente que no se envió a ningún lado y que Encrypchat no puede leer la conversación. No hay "nuestro equipo revisará" en ninguna parte (hay un test que lo verifica: `test/abuse_report_test.dart`).
- Por defecto el reporte bloquea también al contacto: el bloqueo es la única acción con efecto real.

Si en revisión Apple exige un canal donde un humano reciba el reporte, la única salida honesta es el **buzón de contacto del operador** (bloqueante 4) publicado en la ficha y en la política, con la respuesta escrita de que el contenido es E2EE y no se puede aportar desde el servidor. No se debe implementar un envío automático del contenido de un tercero.

## Exportación y criptografía

Encrypchat implementa cifrado propio de la aplicación: X25519 + ChaCha20-Poly1305 (mensajes y media), DTLS-SRTP (llamadas) y, desde F10, AES-256-CBC + HMAC-SHA256 para el fichero de base de datos local.

**Cambio de supuesto (2026-08-12), para el abogado:** el cifrado de la base de datos local llegó con **SQLCipher**, que trae **OpenSSL enlazado estáticamente** dentro de `libsqlcipher` ([phase-8.md](phase-8.md), [audit-f3-storage.md](audit-f3-storage.md)). Dos consecuencias que no existían cuando se escribió este apartado: la app ya no solo incorpora criptografía propia, sino una **biblioteca criptográfica de terceros empaquetada** en el binario, y el inventario declarable cambia. Eso hace más urgente resolver `ITSAppUsesNonExemptEncryption`, que sigue ausente del `Info.plist`. **El valor de esa clave y la conclusión de exención los decide el abogado**; aquí solo queda constancia de que el supuesto de partida cambió.

- [ ] `ITSAppUsesNonExemptEncryption` en `Info.plist`. **Hoy la clave no está declarada**, así que App Store Connect la pedirá en cada envío
- [ ] Determinar con abogado si aplica exención: una app de mensajería E2EE con cifrado no estándar-exento suele requerir autoclasificación anual ante BIS (ECCN 5D992.c) y número de exportación en la ficha de Apple
- [ ] Comprobar requisitos locales del país de la entidad legal (por ejemplo, declaración a ANSSI en Francia)
- [ ] Play no tiene formulario de exportación, pero la responsabilidad de cumplimiento de exportación sigue siendo del desarrollador

## Coherencia de la ficha (copy de tienda)

Reglas para el texto corto y largo de ambas tiendas:

| Se puede decir | No se puede decir |
| --- | --- |
| "Cifrado de extremo a extremo en origen" | "Imposible de hackear / interceptar" |
| "Zero-cloud de contenido: los chats viven en tu dispositivo" | "Nada sale nunca de tu dispositivo" |
| "Relay ciego opcional: solo guarda el sobre cifrado hasta la entrega" | "Cero metadatos" |
| "Llamadas P2P sin servidor de media de Encrypchat" | "Llamadas 100 % privadas / zero-knowledge" |
| "Sin cuentas, sin agenda telefónica, sin analítica" | "Cero metadatos en el dispositivo" |
| "Base de datos local cifrada con SQLCipher (AES-256), clave derivada del almacén seguro del SO" | "Nadie puede leer tus datos ni con el dispositivo en la mano" |
| "Identidad por token criptográfico" | Cifras de usuarios, valoraciones o premios inventados |
| — | "El remitente está autenticado" / "protegido contra suplantación" (F-1 y F-2 de [audit-f10.md](audit-f10.md) siguen abiertos) |

Sobre la fila de SQLCipher: **la palabra ya se puede usar** (dejó de estar prohibida el 2026-08-12,
cuando aterrizó el cifrado de fichero completo), pero nunca sola. Donde se afirme, acompañarla del
alcance real: protege el fichero leído del disco —equipo robado, móvil apagado, backup recuperado,
otra cuenta del sistema— y **no** protege un dispositivo desbloqueado con el llavero accesible, ni
cubre el listado del directorio `media/`, cuyo número de ficheros, tamaños y fechas son metadatos
del sistema de ficheros. Redacción de referencia (aún sin desplegar) en
`apps/web/src/i18n/{es,en}.ts`: FAQ «¿Están cifrados mis datos dentro del dispositivo?» y
`privacy.datos`.

Sobre la última fila: hasta que se cierre F-1, la ficha no puede insinuar autenticación de
identidad del par. La política ya lo declara como límite abierto en las dos rutas.

El copy de la ficha debe pasar por `/seo` y `/legal` antes de enviarse, igual que la landing.

## Orden sugerido

1. Operador: entidad legal, jurisdicción, buzón de contacto → cerrar los huecos de `/privacy` y `/terms`.
2. ~~Operador: `https://encrypchat.com` live con las páginas legales accesibles.~~ Hecho (Dokploy + Cloudflare Tunnel): los enlaces de la app ya resuelven.
3. ~~`/frontend`: reporte y bloqueo de usuarios, enlaces legales dentro de la app, `NSPhotoLibraryUsageDescription`.~~ Hecho.
4. Operador: keystore de release + AAB ([phase-8.md](phase-8.md)); host macOS para el build iOS.
5. Abogado: revisión de privacidad, términos, clasificación por edad y exportación.
6. Envío a revisión con las notas de dos dispositivos.
