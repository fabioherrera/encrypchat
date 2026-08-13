# Auditoría F10 — pase completo sobre el conjunto

**Fecha:** 2026-08-12 · **Alcance:** sistema entero, con foco en interacciones entre capas
**Veredicto:** no apto para beta cerrada hasta cerrar F-1 y F-2.

**Actualización (mismo día, pase de core).** F-1 cerrado, F-5 parcialmente cerrado y F-15
cerrado en `crates/core` (`0.8.0`): EH01 pasa a **EH02**, con prueba de posesión real, sin
revelar la identidad de quien escucha antes de verificar, y con una clave de sesión que cifra el
transporte entero. La mitad de F-2 que vivía en el relay se cerró antes con el sealed sender
`ECS1`. Los cambios rompen formato de wire —los tres van en el mismo corte— y **ninguno está en
vigor hasta que el cliente Flutter llame a la superficie nueva**; el veredicto de arriba sigue
en pie hasta ese cableado y su reauditoría. F-15 apareció al cerrar F-1 y F-5.

**Actualización (pase de relay).** F-8 y F-13 cerrados en `services/relay`. F-8 rompe la API
de `/v1/challenge` y `/v1/pull`, así que también espera cableado Dart. F-13 no rompe nada pero
**exige que el operador configure `ENCRYPCHAT_RELAY_TRUSTED_PROXIES`** en el despliegue
proxeado del repo: sin eso el límite por IP sigue sin servir de nada, y ahora el relay lo dice
en los logs. El borrado antes del ACK durable **queda cerrado** con el lease de entrega, una vez
que el cliente dedupó por `msg_id`: la entrega pasa a ser al menos una vez (dos intentos como
máximo) y cada blob del relay cruza la red dos veces. Coste y residual en
[audit-f5-relay.md](audit-f5-relay.md).

**Actualización (mismo día, pase de cliente).** El cableado está hecho en `apps/client`: la ruta
de relay usa `ECS1` y el `from` declarado ya no existe (F-2), el bloqueo decide sobre tokens
autenticados (F-3), bloquear derriba la llamada en curso (F-4) y el anti-replay que el core dejó
del lado del cliente vive en la base local (menor cerrado, F-12 acotado). El piso de ABI del
cliente subió a `0.8.0`, así que un core viejo no arranca en lugar de degradarse. La señalización
de llamadas sigue **solo P2P** a propósito. Falta la reauditoría, y con ella el veredicto.

**Actualización (segundo pase de cliente).** F-6, F-10 y F-11 cerrados en `apps/client`. Los
mensajes de quien no es contacto ya no desaparecen en el disco: entran por un único punto de
decisión, solo si son texto y dentro de una cuota, y se ven en una bandeja de solicitudes que no
suena. Los adjuntos tienen techo por par y global. El puente FFI zeroiza cada buffer nativo que
llevó una clave o un texto plano, y las tres llamadas con presupuesto de bloqueo salieron del
isolate de UI. Lo que queda de F-10 y F-11 no se puede cerrar desde el cliente y está descrito en
cada sección.

Primer pase sobre el conjunto. Las auditorías previas (`audit-f2-crypto.md` … `audit-f7-calls.md`)
revisaron cada fase por separado; este documento recoge lo que solo aparece al mirar entre capas.

## Hallazgo raíz

Cada fase asumió que la capa de al lado autenticaba al remitente. **Ninguna lo hace.**
`audit-f2-crypto.md` marcó la falta de AAD con remitente como Medium y aplazó el fix a F4;
el fix nunca se implementó. F4 y F5 dieron por buena la autenticación "EH01-grade", y F7
construyó sobre ella la política de llamadas. Una deuda Medium aplazada dos fases quedó
convertida en la raíz de un Critical.

## Estado de hallazgos

| # | Sev | Qué | Bloquea | Estado |
| --- | --- | --- | --- | --- |
| F-1 | **Critical** | EH01 no prueba posesión de clave privada: suplantación P2P con solo la clave pública | Beta | **Cerrado en core** — EH01 sustituido por EH02 (`crates/core/src/handshake.rs`, `0.8.0`). Rompe el wire: los dos extremos tienen que actualizarse |
| F-2 | **Critical** | La autenticación de remitente falta en la capa cripto, no en el relay | Beta | **Cerrado en relay, core + cliente** — `ECS1` cableado en Dart y el `from` declarado eliminado del payload; piso de ABI `0.8.0`. En P2P la autenticación es la de la sesión EH02 (core); `encrypchat_encrypt` sigue sin vincular remitente por sí solo |
| F-3 | High | El bloqueo de contactos es evadible en ambas rutas | Beta | **Cerrado** — el bloqueo decide sobre un token que el atacante no elige: el que sale del criptograma (relay) o el de la sesión EH02 (P2P) |
| F-4 | High | Bloquear no derriba una llamada activa: micro y cámara siguen fluyendo | Beta | **Cerrado** — `block()` cuelga antes de aplicar el bloqueo (`call_service.dart`), con tests |
| F-5 | High | El puerto P2P revela la identidad permanente sin autenticar | 1.0 | **Parcial** — quien escucha ya no revela nada hasta verificar, ni en el handshake ni en la sesión (F-15 cerrado); queda el residuo inherente: quien llama se identifica ante una identidad desechable |
| F-6 | High | Un desconocido puede llenar el disco con adjuntos invisibles en la UI | 1.0 | **Cerrado** — un único punto decide qué entra: los no-contactos van a una bandeja de solicitudes de solo texto con cuota (20 remitentes × 5 mensajes × 4 KiB), sin sonar; media y llamadas de desconocidos se rechazan. Cuota de disco por par (512 MiB) y global (2 GiB) en `MediaStore` |
| F-7 | High | El copy público sitúa el fallo de autoría "en la ruta de relay": es falso | Beta | **Cerrado** — `apps/web/src/i18n/{es,en}.ts` describen las dos rutas como autenticadas y dicen en voz alta que la página anterior lo daba por abierto; `legal-f7-calls.md` y `audit-f5-relay.md` recogen el encuadre correcto. No queda superficie con el texto viejo |
| F-8 | Medium | Desafío de relay sobreescribible → bloqueo de buzón y pérdida real de mensajes | 1.0 | **Cerrado end-to-end** — el desafío deja de tener dueño por token: `challenge_id` opaco, sin `dest_token`, varios vivos a la vez con techo global, y no se consume si la prueba falla. Rompió la API de `/v1/challenge` y `/v1/pull`, y el cliente Dart ya habla el contrato nuevo. Un relay anterior a F-8 se detecta y se reporta como desajuste de protocolo en vez de fallar en bucle |
| F-9 | Medium | Cola inbound de 256 × 16 MiB → OOM remoto | 1.0 | Abierto |
| F-10 | Medium | El puente Dart no limpia copias de la clave privada; contradice el contrato FFI | 1.0 | **Cerrado en lo que el lenguaje permite** — todo buffer nativo con clave o texto plano se pone a cero antes de liberarse, en las dos direcciones. Queda el heap de Dart, que no se puede zeroizar: cerrarlo exige que la clave no cruce la frontera (propuesta para el core, no forzable desde el cliente) |
| F-11 | Medium | Llamadas FFI bloqueantes en el isolate de UI; contradice el contrato FFI | Beta (UX) | **Cerrado para las bloqueantes** — `nodeSend`, `nodeConnect` y `nodeStop` corren en un isolate propio (`core_worker.dart`); la UI ya no se congela esperando el ACK de un par. Las llamadas acotadas (cripto, DB, token) siguen en el principal a propósito |
| F-12 | Medium | Reescritura remota del historial reutilizando `msg_id` | 1.0 | **Cerrado** — lo entrante se inserta con `insertMessageIfNew` (ignora el conflicto) en **las dos** rutas, así que un id repetido no reescribe la fila ni le pone fecha nueva; en media hay además comprobación previa y borrado del fichero si el insert pierde la carrera. Residual: un id ya podado deja el blob reabrible, aunque el mensaje no se reescriba |
| F-13 | Medium | Límite por IP inútil detrás de proxy + sin techo global de disco | 1.0 | **Cerrado** — `X-Forwarded-For` con lista de proxies de confianza, detección en caliente del despliegue proxeado, y techo global de bytes que rechaza sin desalojar. Requiere que el operador configure `ENCRYPCHAT_RELAY_TRUSTED_PROXIES` |
| F-14 | Low-Med | El informe de abuso viaja por el portapapeles del sistema | 1.0 | Abierto |
| F-15 | Medium | La cabecera `EC04` viaja en claro por el socket: el `sender_token` de cada trama es visible para un observador de la red | 1.0 | **Cerrado en core** — transporte cifrado con clave de sesión de EH02, una por sentido (`crates/core/src/transport.rs`, `0.8.0`). Queda visible el tamaño por encima de 512 bytes |

Ningún hallazgo puede pasar a "aceptado" sin motivo escrito y firma del operador.

---

## F-1 — Critical — EH01 no autentica al par

`crates/core/src/net.rs:531-581` · `crates/core/src/crypto.rs`

La prueba de EH01 es `encrypt(pubkey_del_par, nonce_propio || nonce_del_par || token_propio)`.
`encrypt` genera una clave efímera de emisor, así que **cifrar hacia alguien solo requiere su
clave pública**. `verify_proof` descifra con la privada local, comprueba los dos nonces, y
valida que el token declarado sea `SHA-256(pubkey ofrecida)`. Todo eso es información pública.

Ataque, sin privilegios de red:

1. Mallory obtiene la tarjeta de contacto de Alicia — o simplemente conecta al puerto de
   Alicia y lee su oferta, que va en claro (ver F-5).
2. Mallory conecta al nodo de Beto con el token y la pubkey de Alicia.
3. Beto responde con su oferta. Mallory calcula la prueba con la pubkey de Beto, que acaba
   de recibir.
4. Beto registra la sesión como Alicia y acepta tramas con `sender_token = alicia`.

Resultado: mensajes, fotos y **llamadas** atribuidos a Alicia. La mitigación de F7 (llamadas
solo P2P, `messaging_service.dart:529-534`) no mitiga nada, porque el P2P tampoco autentica.

**Fix.** Prueba real de posesión: ECDH estático-estático en la prueba, o exigir que el
`eph_pub` del blob sea la pubkey ofrecida por el par, de modo que descifrar requiera la
privada declarada. Test negativo obligatorio: un atacante que solo tiene la pubkey falla.

### Cerrado — EH02 (core `0.8.0`, `crates/core/src/handshake.rs`)

Se eligió el ECDH estático-estático, reutilizando el mismo primitivo de dos capas que `ECS1`
(`sealed::two_layer_seal`). La alternativa mínima —exigir que el `eph_pub` del blob de prueba
sea la pubkey ofrecida— es criptográficamente equivalente en el fondo, pero convertía la clave
de identidad en la efímera de `encrypchat_encrypt` y dejaba una construcción cuyos blobs son
indistinguibles de un mensaje normal. Un primitivo con dominio propio y dos capas evita esa
confusión entre protocolos y deja una sola construcción que auditar para las dos rutas.

Flujo (cuatro mensajes, detalle en `docs/threat-model.md` §6.2):

```text
1. →  EH02 || ver || nonce_i
2. ←  e_r_pub || nonce_r                    sin identidad
3. →  prueba del que llama, sellada a e_r_pub
4. ←  prueba del que escucha, sellada a la clave ya autenticada del que llama
```

El mensaje 3 se sella contra la **efímera** de quien escucha, y por eso quien llama puede
autenticarse primero sin saber todavía con quién habla: eso es lo que además permite cerrar la
parte de F-5 que se podía cerrar. Las dos pruebas llevan carga útil vacía; todo el binding
(versión, rol, los dos nonces, la efímera) va en el AAD.

Tests: `net::tests::attacker_with_only_the_public_key_fails_the_handshake` reproduce el ataque
de arriba sobre un socket real —Mallory tiene la pubkey de Alicia y nada más— y comprueba
además que la Alicia real, con su privada, sí entra. En unidad,
`handshake::tests::public_key_alone_cannot_impersonate` y `proof_is_bound_to_session_and_role`.

**Rompe compatibilidad**: un par en `0.7.x` falla en la magia del mensaje 1. Aceptado pre-1.0.

## F-2 — Critical — La autenticación de remitente falta en la capa cripto

`crates/core/src/crypto.rs:11-12, 43-95` · `apps/client/lib/services/messaging_service.dart:361-364, 609-611`

`MSG_AAD` sigue siendo una constante. El `from` que el cliente cree vive **dentro del texto
plano del sobre**, no en el transporte.

Consecuencia sobre el arreglo del relay en curso: autenticar quién *deposita* un blob no
impide que el contenido declare otro remitente, porque el relay es ciego y no puede leer el
sobre. Un atacante hace PoP con su propia identidad y escribe `"from": "<contacto_tuyo>"`.

**Fix.** Vincular el remitente en la capa AEAD: ECDH estático-estático mezclado en la
derivación de clave, y `sender_token` como AAD. Descifrar correctamente pasa a **probar**
autoría. Cierra el relay y el P2P con un solo cambio. Requiere versionar el formato; sin
usuarios reales, se recomienda corte limpio.

### Cerrado en la ruta de relay — cableado del cliente (2026-08-12)

`apps/client/lib/core/encrypchat_core.dart` · `services/messaging_service.dart`

El corte es limpio, como se recomendó: el payload de relay pasó a ser **los mismos bytes que
lleva el camino P2P** —texto UTF-8 a secas o un `EM01`— sellados con `encrypchat_sealed_seal`.
El sobre JSON con `v`/`from`/`body` desapareció; no quedó un campo de remitente que ignorar.

- Envío: `_enqueueSealed` es el único punto que habla con el relay, y sella. El tope de 256 KiB
  se comprueba sobre el blob (`136 + payload`), que es determinista, así que el error por
  adjunto grande se da antes de gastar el sellado. Media dejó de viajar en base64: el mismo
  cupo admite ahora un tercio más de imagen.
- Recepción: `handleRelayBlob` autentica primero, y de ahí sale el token con el que se decide
  todo lo demás. Sin `AuthFailed` no hay atribución posible y con `AuthFailed` tampoco: el
  remitente declarado ya no existe, así que no hay a qué caer.
- Piso de ABI del cliente: `0.7.0` → **`0.8.0`**. Un core viejo no tiene los símbolos nuevos y
  la ruta de relay no tiene alternativa; falla al cargar con una frase, no con un símbolo.
- Cada código de error del core queda separado en la UI (`RelayDropReason`), y solo
  `AuthFailed` se presenta como hostil. Un mensaje viejo nunca se muestra como ataque.

Un blob sellado no lleva el token ni la pubkey del emisor en claro; un test lo comprueba
buscando esos bytes dentro del blob encolado.

## F-3 — High — El bloqueo es evadible

`apps/client/lib/services/messaging_service.dart:612-617, 685-691`

El bloqueo se decide sobre un identificador que el atacante elige. Por relay, cambiando
`from`; por P2P, por F-1. Peor: el bloqueado puede declarar el token de un contacto de
confianza y su mensaje aparece **dentro del hilo de esa persona**.

Invalida un control ya prometido en la UI (`safety_actions.dart:19-24`). Se cierra con F-2.
Mientras tanto, el texto del diálogo no debe prometer lo que el código no cumple.

### Cerrado — el bloqueo ya no decide sobre un dato elegible

Por relay el token sale del criptograma (`sealed_open`), por P2P es el de la sesión EH02. En
las dos rutas el identificador que se compara contra la lista es uno que el atacante no puede
escribir, así que el escenario del hilo contaminado —un bloqueado apareciendo dentro de la
conversación de un contacto de confianza— deja de ser posible. El corte sigue siendo único y
sigue estando antes de descifrar en P2P y antes de persistir en relay.

Queda un límite honesto que el diálogo sí puede decir: el bloqueo es local y unilateral, no
impide que la otra parte siga escribiendo a un buzón que este dispositivo ya no vacía.

## F-4 — High — Bloquear no corta una llamada en curso

`apps/client/lib/services/messaging_service.dart:134-140` · `session_controller.dart:158-161` · `call_service.dart:16-18, 173-177`

`block()` no toca `CallService`. El `RTCPeerConnection` es UDP directo y no pasa por el nodo,
así que micro y cámara siguen transmitiendo. Y como a partir del bloqueo se descartan todas
las señales del par, también se descarta su `hangup`: la llamada queda colgada hasta que la
víctima cuelgue a mano.

**Fix.** Si `calls.peer.token == token`, colgar antes de aplicar el bloqueo.

### Cerrado (2026-08-12)

`MessagingService.block()` invoca un gancho `onBlockPeer` que `CallService` instala en su
constructor (igual que `onCallSignal`, para no invertir la dependencia). Se ejecuta **antes** de
aplicar el bloqueo, y ese orden es el fix: mientras el token no está bloqueado, `hangup()`
todavía puede mandarle el `hangup` al par, así que la llamada también se cae del otro lado en
vez de quedar colgada. Un fallo del cierre se registra y se sigue: bloquear es el control que
pidió la usuaria, la llamada es el efecto.

Tests (`test/call_block_test.dart`): bloquear con llamada activa deja la fase en `ended` y el
stream local liberado; bloquear a un tercero no toca la llamada; el timbre de un par que se
bloquea mientras suena se corta; la diferencia de mayúsculas en el token no salva la llamada; y
un cierre que lanza no impide el bloqueo. `getUserMedia` y `RTCPeerConnection` necesitan el
plugin nativo, que `flutter test` no carga, así que el estado de llamada se monta con un doble
del stream y lo que se comprueba es el camino de derribo.

De paso: `_reset()` escribía en los renderers sin comprobar si estaban inicializados, y una
llamada derribada antes de mostrarse (rechazar el timbre, o bloquear mientras suena) nunca los
inicializa. Lanzaba `'Call initialize before setting the stream'` desde dentro del cierre.

## F-5 — High — El puerto P2P revela la identidad antes de autenticar

`crates/core/src/net.rs:615-617`

En rol `Acceptor` se lee la oferta y se escribe la propia **antes** de verificar nada.
Cualquiera que abra un TCP con una identidad desechable obtiene token y clave pública. Un
escaneo en red compartida mapea `IP → identidad permanente`, y encadena con F-1: la pubkey
es todo lo que hace falta para suplantar.

**Fix.** Exigir la prueba del que llama antes de emitir la oferta propia (EH01 a tres pasos).
Conviene hacerlo junto con F-1.

### Parcial — lo que EH02 consigue y lo que no

**Conseguido.** Quien escucha responde con una efímera de un solo uso y un nonce, y no emite
nada identificable hasta haber verificado el mensaje 3. Por tanto: un observador pasivo de la
red no aprende ninguna identidad de un handshake; quien abre un TCP y no puede probar **ninguna**
identidad no obtiene nada; y un par bloqueado se rechaza entre el 3 y el 4, así que ni siquiera
sabe quién le respondió. El escaneo anónimo de una wifi ya no mapea `IP → identidad`.

**No conseguido.** Quien llama sigue teniendo que identificarse primero, y un atacante que
genere una identidad desechable y complete el handshake obtiene la identidad de quien escucha.
No es un descuido de implementación: con X25519 la prueba es un DH, y un DH solo lo puede
calcular quien conoce la clave del verificador, así que el primero en autenticarse tiene que
ser el que ya conoce al otro. Es la propiedad de Noise `XX`, no la de `IK`.

**Cómo se cerraría.** Que quien llama conozca la clave pública del destino al marcar (patrón
`IK`): entonces puede cifrar su propia identidad hacia esa clave y verificar a quien escucha
antes de revelarse. Requiere pasar la pubkey en el dial —hoy se pasa el token, que es un hash—,
o sea tocar la superficie FFI y el cliente, que ya guarda la pubkey de cada contacto.

Se descartó el "knock" (que quien llama demuestre conocer el token del destino antes de que el
otro conteste): quien escucha ya no revela nada antes de verificar, así que no añadía nada, y
en cambio filtraba a cualquier impostor que conteste **a quién** estaba buscando quien llama.

Ojo con el alcance: al escribirse, esto protegía el handshake pero no la sesión, cuyas tramas
iban en claro. F-15 cerró ese hueco en el mismo corte, así que la propiedad ahora vale también
para la conversación.

## F-6 — High — Adjuntos de desconocidos, invisibles y sin cuota

`apps/client/lib/services/messaging_service.dart:733-762` · `chats_page.dart:104`

Se persiste cualquier mensaje que descifre bien, sin comprobar que el remitente sea contacto.
La lista de chats itera sobre **contactos**, así que esos mensajes quedan en disco y no
aparecen en ninguna pantalla: no se pueden ver, ni borrar, ni bloquear al emisor. Hasta
12 MiB por trama, en bucle.

**Fix.** Política explícita para no-contactos aplicada en un único punto, y cuota de
almacenamiento por par y global.

### Cerrado (2026-08-12, segundo pase de cliente)

**La política: aceptar en una bandeja acotada, no descartar.** Descartar de plano era la otra
opción y se descartó por lo que un token *es*: algo hecho para darlo por fuera de la app (QR, una
bio, un papel). Con la regla de descartar, quien recibe tu token no puede escribirte hasta que lo
agendes, y lo peor es que ninguno de los dos se entera: el relay acepta el blob igual, así que el
emisor ve un envío correcto y el destinatario nunca ve nada. Aceptar mantiene ese flujo y acota lo
que cuesta un desconocido, que era el verdadero problema de F-6:

- **Solo texto**, y hasta 4 KiB. Un adjunto de quien no es contacto se rechaza **antes** de
  escribirse: sellar primero y esconder después es exactamente lo que dejó pasar los bucles de
  12 MiB.
- **No suena.** Una invitación de llamada de un desconocido se descarta sin timbre y sin dejar
  nada en disco. El caso de acoso pesa más que el de la llamada legítima de alguien sin agendar.
- **Cuota**: 20 remitentes pendientes, 5 mensajes cada uno. El techo total de un desconocido son
  unos 400 KiB de texto, contra los 12 MiB por trama de antes.
- **Sin notificación.** La bandeja se mira, no avisa.

El punto único es `_acceptPayload` en `messaging_service.dart`, por donde pasan las dos rutas
después de autenticar al remitente. Ese sitio es el único posible: antes de autenticar no se sabe
sobre quién se decide, y repartir la regla entre las dos rutas es cómo apareció el hallazgo. El
orden dentro también importa: bloqueo primero, política después, escritura al final.

**La bandeja.** Tabla `requests` (esquema v6) con token, clave pública si la hay, primera y última
vez, contador y si llegó por relay. La admisión y el contador van en una transacción, así que la
cuota no se puede pasar mandando en paralelo. `RequestsPage` muestra cada solicitud con su copy
—qué se aceptó y qué no— y tres acciones: aceptar (crea el contacto), descartar (borra mensajes y
media) y bloquear. Aceptar necesita la clave pública, que en relay sale del criptograma pero en
P2P no viaja en la trama `EC04`; en ese caso la UI lo dice en vez de crear un contacto al que no
se puede responder.

**Cuota de disco.** `MediaStore.ensureRoomFor` comprueba, antes de escribir, 512 MiB por par y
2 GiB en total, sumando el tamaño real de los ficheros sellados. Al pasarse, el adjunto se
rechaza y la UI muestra el aviso: el disco lo llena el otro lado, así que el que se entera tiene
que ser el dueño del dispositivo. Borrar la conversación libera los bytes —media primero, filas
después, porque una fila sin fichero es un adjunto roto y un fichero sin fila es un byte que nadie
va a encontrar nunca—, y borrar un contacto ahora pregunta por el historial en lugar de dejarlo
huérfano, que era la otra mitad de la invisibilidad.

Tests (`test/stranger_policy_test.dart`): el texto de un desconocido entra en la bandeja y no en
la lista de chats; su adjunto y su timbre se rechazan sin tocar disco; la cuota por remitente y la
global cortan en el número exacto; aceptar convierte la solicitud en contacto y a partir de ahí sí
entran adjuntos; descartar con bloqueo deja el token bloqueado y la conversación vacía; y la cuota
de `MediaStore` rechaza por par y por total.

## F-7 — High — Copy público falso sobre el alcance del fallo

`apps/web/src/i18n/es.ts:211` · `en.ts:211`

Dice que el remitente sin autenticar es cosa "de la ruta de relay". Por F-1 aplica también a
P2P, y la frase induce a lo contrario justo donde el lector decide si una llamada entrante es
de quien dice ser. Mismo error en `docs/legal-f7-calls.md` y `docs/audit-f5-relay.md:23`.

## F-8 — Medium — Desafío de relay sobreescribible

`services/relay/src/store.rs:152-178, 220-236`

El desafío está indexado por `dest_token`, hay uno solo por buzón y cualquiera puede pedirlo
sin autenticarse. Un tercero que pida desafíos en bucle sobreescribe el `eph_secret` y el
`pull` de la víctima falla — y el desafío se consume igualmente aunque la prueba falle.

Resultado no documentado antes: el buzón nunca se vacía, alcanza la cuota y los mensajes que
llegan después **se pierden**. Es censura dirigida contra un token, desde una sola IP, dentro
del presupuesto de rate-limit. (Cómo se ve eso desde fuera cambió al cerrarse B-3: un buzón
sobre cuota ya no responde `507` sino como una aceptación, para no delatar la presencia del
destinatario. La denegación dirigida sigue existiendo y ahora es además silenciosa para quien
envía — ver `audit-f5-relay.md`.)

**Fix.** `challenge_id` opaco por desafío, varios vivos a la vez, y no consumir en fallo.

### Cerrado en el relay

`services/relay/src/store.rs` · `api.rs`

Se fue un paso más allá de lo propuesto: **el desafío deja de tener destinatario**. Un desafío
es un par efímero y un nonce, que son iguales para cualquier buzón; el destino ya viaja dentro
de la prueba (`pop_verify` mete `dest_token` en el transcript). Así que `/v1/challenge` no
recibe cuerpo, no aprende a qué buzón apunta nadie, y la tabla se indexa por un `challenge_id`
opaco.

Por qué no un techo por token, que era la vía propuesta: cualquiera de sus dos resoluciones
reconstruye el hallazgo. Si al llenarse se desaloja el más viejo, el atacante vuelve a echar
el desafío de la víctima con solo ganar la carrera de unos segundos; si al llenarse se rechaza,
el atacante llena el cupo de la víctima y es ella la que no puede pedir. El espacio de nombres
por token **es** el arma. Sin él, el único techo posible es global: 50 000 desafíos vivos,
recorte del más antiguo. Para tirar un desafío concreto hay que empujar la tabla entera en la
ventana entre el desafío de esa persona y su recogida, que es un flood genérico, no censura
dirigida. Acotar ese caudal es trabajo del proxy (F-13).

El desafío se consume **solo si la prueba verifica**: los ids no se adivinan, así que el único
que puede gastar uno es aquel a quien se le dio, y quemarlo en el fallo sería una versión
pequeña del mismo problema. Consumirlo en el acierto es lo que impide reproducir una prueba
capturada.

Regresión cubierta por `third_party_challenges_cannot_lock_a_mailbox`, que es literalmente el
ataque descrito arriba.

**Rompe la API.** `/v1/challenge` devuelve `challenge_id` y ya no acepta `dest_token`;
`/v1/pull` exige `challenge_id`. El cliente Dart tiene que actualizarse; hasta entonces el
relay no es utilizable desde la app.

## F-9 — Medium — OOM remoto por la cola inbound

`crates/core/src/net.rs:167, 34, 670-691`

Canal de 256 posiciones × 16 MiB por trama = hasta 4 GiB residentes. `ffi-contract.md:134-137`
afirma que un par no autenticado no puede fijar memoria: cierto pre-handshake, y ahí se detuvo
el análisis. **Fix:** presupuesto en bytes, no en número de mensajes.

## F-10 — Medium — El puente Dart no zeroiza

`apps/client/lib/core/encrypchat_core.dart:637-641, 613-617` vs `docs/ffi-contract.md:100-102`

El contrato dice que los buffers del llamante son suyos para zeroizar. No se zeroiza ninguno.
La clave de identidad se copia al heap nativo en **cada** `decrypt` y en cada `popProof`
(cada 8 s por el sondeo) y se libera sin borrar. El cuidado de Rust con `Zeroizing` lo deshace
el puente sistemáticamente.

### Cerrado hasta donde el lenguaje llega (2026-08-12, segundo pase de cliente)

Dos helpers, y ninguna excepción. `_freeSecret` pone el buffer a cero antes de `calloc.free`, y lo
usan **todos** los stagings que llevaron material sensible, no solo los evidentes: los secretos de
identidad de `decrypt`, `popProof`, `sealedSeal`/`sealedOpen`, `identityToken` e `identityPublicKey`,
la `db_key` —que abre el almacén entero— y también el lado `data` de un sellado, que es el cuerpo
del mensaje. `_takeBuffer` hace lo simétrico con los buffers que reserva el core y devuelve al
llamante: copia, borra el original y después llama a `encrypchat_free`, que es un free normal y
devolvería esas páginas legibles al asignador. Eso cubre cada texto plano descifrado, cada blob
sellado y cada trama entrante.

Lo que **no** se puede cerrar desde aquí es la copia del lado Dart. Un `Uint8List` vive en el heap
del recolector, que puede moverlo y duplicarlo, y el lenguaje no ofrece ninguna forma de prometer
que no quedó nada: la clave de identidad está en memoria gestionada mientras haya sesión, y el
almacén seguro la entrega como `String` en base64, que es inmutable por definición. Lo poco que
había a mano se hizo: la copia intermedia que `IdentityService` decodifica se borra en cuanto se
guarda la definitiva.

**La propuesta de fondo, para el core.** Que la clave no cruce la frontera y el descifrado ocurra
dentro del núcleo elimina la superficie en vez de limpiarla, y es la dirección correcta —el nodo ya
tiene la clave, así que el puente la está pasando por segunda vez—, pero es un cambio de la
superficie FFI: `encrypchat_decrypt` y `encrypchat_sealed_open` pasarían a tomar un handle en lugar
de 32 bytes, con un modo sin nodo arrancado para el arranque y el sondeo del relay. No se fuerza
desde el cliente; queda encargado al core.

## F-11 — Medium — FFI bloqueante en el isolate de UI

`docs/ffi-contract.md:118-121` vs `messaging_service.dart:177-183, 351, 458, 554` · `call_service.dart:332-351`

`nodeSend` bloquea hasta 15 s. Un par que acepta y no contesta congela la interfaz, con riesgo
de ANR en Android. Durante una llamada, cada candidato ICE dispara un envío bloqueante.

### Cerrado para las tres llamadas bloqueantes (2026-08-12, segundo pase de cliente)

`CoreWorker` (`apps/client/lib/core/core_worker.dart`) es un isolate con su propia
`DynamicLibrary`, que es lo que obliga el contrato: los punteros no se comparten, la biblioteca se
recarga allí. Se le pasan las tres llamadas con presupuesto de bloqueo —`nodeSend` (15 s),
`nodeConnect` (10 s) y el `nodeStop`— y nada más: la cripto, la base de datos y el token están
acotados en microsegundos y moverlos solo añadiría latencia y copias.

Los detalles que hacen que esto sea seguro y no una carrera:

- El handle del nodo se comparte **por dirección**, no por puntero: el isolate principal arranca el
  nodo y le pasa el entero al worker, que lo reconstruye. El core es dueño del objeto; los dos
  lados solo lo referencian.
- Parar el nodo va por la **misma cola** que los envíos, así que nunca se libera con una llamada
  dentro. El principal se desprende del handle antes de encolar el `stop`: si el worker no
  responde, no queda nadie que pueda usar un puntero liberado.
- Si el isolate no arranca —un entorno sin `Isolate.spawn`, que es el caso de `flutter test`—, el
  cliente sigue funcionando llamando en el principal. Degradar la fluidez es aceptable; no poder
  mandar un mensaje no lo es.
- Los errores del core cruzan como código, no como excepción serializada, así que `CoreException`
  llega al llamante con su código intacto y la UI sigue distinguiendo lo que ya distinguía.

Tests (`test/core_worker_test.dart`): el worker abre el core y responde en su propio isolate; un
envío sin nodo arrancado devuelve el error del core y no un fallo de transporte; y el cierre
completa las llamadas pendientes con error en vez de dejarlas colgadas.

Lo que queda de UX: el envío sigue siendo una espera, ahora sin congelar la pantalla. Un botón de
cancelar exige que el core acepte cancelación, que hoy no tiene.

## F-12 — Medium — Historial reescribible por el par

`messaging_service.dart:718-728` · `local_database.dart:223-229` · `media_store.dart:44-57`

`msg_id` lo elige el emisor y se usa como clave con `ConflictAlgorithm.replace`. Reenviar una
trama con un `msg_id` ya usado **sustituye el mensaje anterior**, sin traza, y puede moverlo de
conversación. Grave para un producto cuyo flujo de reporte asume un historial fiable.

## F-13 — Medium — Rate-limit inútil detrás de proxy, y sin techo de disco

`services/relay/src/limit.rs` · `api.rs:121-127` · `main.rs:66-70`

El despliegue del repo es con proxy, así que todas las peticiones comparten IP: un solo
atacante agota el bucket y el relay devuelve `429` **a todos**. El control anti-abuso se
convierte en amplificador de denegación de servicio. Además no hay techo global de
almacenamiento, solo cuota por token y purga por TTL.

### Cerrado en el relay

`services/relay/src/client_ip.rs` (nuevo) · `store.rs` · `README.md` · `deploy/cloudflared/`

**Quién paga el bucket.** `X-Forwarded-For` se honra solo si la conexión viene de una
dirección que el operador listó en `ENCRYPCHAT_RELAY_TRUSTED_PROXIES` (direcciones o CIDR), y
solo hasta donde llega esa lista: se recorre la cadena por la derecha y se cobra a la primera
dirección que el operador no avala, de modo que un cliente que añada saltos falsos no puede
quitarse el que le puso su propio proxy. Sin la variable el encabezado se ignora entero, que
es el único default seguro. Una lista malformada aborta el arranque en vez de degradar a
"no confiar en nadie", que se vería configurado y se comportaría como el bug.

**Detección.** Si las primeras 100 peticiones vienen todas de la misma dirección y no hay
proxy configurado, se emite un warning nombrándola. Es la forma que tiene el despliegue mal
configurado de verse desde dentro, y un log en el sistema vivo lo caza mejor que un párrafo
en un README. En el arranque solo se informa del modo: correr sin proxy es legítimo y un
warning permanente enseña a ignorar warnings.

**Techo de disco.** `ENCRYPCHAT_RELAY_MAX_TOTAL_BYTES` (1 GiB) sobre los bytes vivos de todos
los buzones; al superarlo, `507 relay storage unavailable`, con aviso al 90%. **No se desaloja
nada para hacer sitio**: las únicas filas que el relay borra son las caducadas y las
entregadas. Una política de presión que tirara blobs vivos le daría a cualquiera una forma de
expulsar mensajes ajenos llenando el disco — más barata y más silenciosa que el propio F-8.
Rechazar es peor para quien envía, que se entera, y mejor para todos los demás. Lo que compra
el techo, dicho sin adornos: convierte "llenar el disco hasta que SQLite falle" en "el relay
rechaza escrituras nuevas y sigue entregando lo que ya tiene", y se recupera solo según se
vacían buzones. No impide que un flood deje el relay inútil para mensajes nuevos.

## F-14 — Low-Medium — El informe de abuso pasa por el portapapeles

`apps/client/lib/screens/safety_actions.dart:140` · `models/abuse_report.dart:42-69`

Relaciona identidad de víctima y de agresor, escrito por alguien en situación de acoso, y sale
por un canal que leen gestores de portapapeles y teclados de terceros, y que en escritorio se
sincroniza a la nube. El propio informe afirma que "no se envió a ningún lado", lo que deja de
ser cierto al copiarlo.

## F-15 — Medium — La cabecera de trama viaja en claro por el socket

`crates/core/src/frame.rs:1-10` · `crates/core/src/net.rs`

Encontrado al cerrar F-5. EH02 autentica identidades pero **no cifra el transporte**: una vez
abierta la sesión, cada trama `EC04` va con su magia, su `msg_id` y su `sender_token` en claro
sobre TCP. Solo el payload es E2EE. Un observador de la red que no aprende nada del handshake
aprende la identidad del emisor en el primer mensaje que se envíe, así que la propiedad que da
F-5 se limita a las conexiones que no llegan a hablar.

También significa que el canal no está atado criptográficamente al handshake: un atacante de
red puede reenviar la sesión entera entre las dos puntas. No puede leer nada —el contenido va
cifrado hacia la clave estática del par— pero sí observar, retrasar y descartar.

### Cerrado en core (`0.8.0`, mismo corte de wire que EH02)

`crates/core/src/transport.rs` · `handshake.rs` · `net.rs`

EH02 pasa a llevar **una clave efímera por extremo** —la de quien llama viaja en el mensaje 1,
la de quien escucha ya estaba en el 2— y las dos entran en el AAD de las dos pruebas, así que un
atacante en medio no puede sustituirlas. De ahí sale la clave de sesión, con el esquema `XX`
completo (`ee || es || se || ss || transcript`), y se parte en **una clave por sentido**.

Cada registro de una sesión establecida es ahora `len(4) || AEAD(k_dir, contador)` sobre
`kind(1) || payload_len(4) || payload || relleno`. La cabecera `EC04` y el byte de tipo viajan
dentro del cifrado: un observador ve un prefijo de longitud y bytes opacos. El test
`net::tests::nothing_identifying_is_readable_on_the_wire` proxea la conversación entera y busca
en ella los tokens, las claves públicas y la trama; ninguno aparece.

**Orden y repetición.** El nonce es el contador de la dirección y nunca viaja: el receptor solo
prueba el siguiente. Repetir, reordenar, borrar o inyectar una trama dentro de una sesión falla
el tag y cierra la sesión. Es la diferencia con el replay del relay, donde no hay sesión a la que
anclarse. Un registro rechazado no consume contador, así que inyectar basura no desincroniza el
flujo por su cuenta — aunque no importa mucho, porque el bucle lector corta al primer fallo.

**Secreto hacia adelante: por sesión, no por mensaje.** Las dos efímeras mueren con el
handshake, de modo que quien grabe el tráfico y luego consiga las **dos** claves de identidad no
descifra esa conversación. Dentro de una sesión no hay ratchet: una clave de sesión comprometida
expone la sesión entera en ese sentido.

**Lo que sigue visible:** el tamaño por encima de 512 bytes de texto plano (por debajo todo sale
igual, así que un ACK no se distingue de un mensaje corto), el volumen, los tiempos, y que el
tráfico es de Encrypchat por el `EH02` del primer mensaje. Rellenar más no se hizo a propósito:
no esconde volumen ni tiempos, y el observador ya tiene el par de IPs, que es el dato caro.
Queda declarado en [threat-model.md](threat-model.md) §5 y §6.2.

---

## Anti-replay del relay — dónde vive el conjunto de ids (cliente, 2026-08-12)

`ECS1` impide falsificar y alterar, no duplicar: un blob capturado se reencola y vuelve a abrir,
auténticamente. El core devuelve un `msg_id` estable entre replays y acota la ventana temporal; el
conjunto de ids vistos es del cliente, y quedó así:

| Pieza | Decisión |
| --- | --- |
| Dónde | Tabla `seen_sealed (msg_id PRIMARY KEY, sent_at_unix)` en la base local, o sea dentro de SQLCipher. Sobrevive a reinicios, que es el punto: si no, cualquiera espera a que la app se cierre |
| Cómo se decide | El `INSERT` **es** la comprobación (`ConflictAlgorithm.ignore`, se mira si insertó). Dos pulls a la vez sobre el mismo blob no pueden ganar los dos |
| Cuándo | Después de autenticar y de aplicar la lista de bloqueo, antes de persistir el mensaje. Un remitente bloqueado no gasta una fila |
| Poda | Por `received_at_unix`, la hora de llegada que anota este dispositivo, no el `sent_at` que elige el remitente — con esa columna el que inunda deja de gobernar qué se olvida. Fuera de la ventana el blob ya no abre (`Expired`), así que recordar su id no compra nada |
| Techo | 20 000 no es tope duro: es marca de aviso, y solo se registra en log. El tope duro son 200 000 ids, desalojando por fecha de llegada, y dentro de la ventana no se desaloja nada |
| Reloj | Inyectable en `MessagingService.clock`: el `sent_at` va dentro del criptograma y no se puede antedatar desde fuera, así que mover el reloj es la única forma de probar la expiración y la poda |

El orden importa, y esta parte estuvo mal escrita hasta que la auditoría del threat model la miró
(B-1). Decía que un id se podía grabar aunque el mensaje fallara al guardarse, *"porque el relay
ya borró el blob en el pull, así que no hay una segunda entrega que perder"*. Era cierto — y dejó
de serlo el día que el relay pasó a dejar el blob en lease 60 s. Con el lease, grabar el id antes
de guardar el mensaje hacía que la reentrega se descartara como replay: la función de durabilidad
se anulaba a sí misma en el único escenario para el que existe.

Ahora el id se graba **después** de que el mensaje entra, con un conjunto en memoria de ids en
vuelo para no procesar dos veces dentro del mismo proceso. La distinción es explícita: lo que
queda *resuelto* —guardado, o rechazado por un veredicto que una segunda copia no cambiaría, como
un payload ilegible— graba el id; lo que es *reintentable* —sin cupo, sin espacio— no lo graba, y
una excepción por el camino tampoco.

**Deduplicación legítima.** El id de la fila pasó a ser el `msg_id` sellado en lugar de uno nuevo
por blob, así que la clave del mensaje y la del anti-replay son la misma: un blob repetido no
puede aparecer como mensaje distinto ni siquiera si la tabla de ids fallara. Lo que **no** cubre
es un mismo texto reenviado a mano por el par: eso es un mensaje nuevo con su propio `msg_id`, y
debe seguir apareciendo dos veces.

## Menores registrados

| Ubicación | Nota |
| --- | --- |
| `net.rs:245-249` | `send_to_token` solo consulta la lista de bloqueo si el token parsea; falla cerrado por accidente, no por diseño |
| `net.rs:263-268` | `try_recv` con mutex envenenado devuelve `Empty` (9) para siempre: fallo permanente indistinguible de "no hay mensajes" |
| `net.rs:105-110` | `is_blocked` falla cerrado; `limit.rs:46` falla abierto. Ambas correctas en su contexto, conviene documentarlas juntas |
| ~~`messaging_service.dart:643-651`~~ | Cerrado: el id del mensaje es el `msg_id` sellado y se persiste en `seen_sealed` (esquema v5) antes de guardar nada — ver *Anti-replay* abajo. En P2P sigue sin ventana |
| `call_signal.dart:41-83` | `callId` remoto de hasta 128 caracteres arbitrarios, sin validar formato |
| ~~`.github/workflows/check.yml`~~ | Cerrado: `cargo audit` + `npm audit` en un job propio con cron nocturno, `flutter analyze` en el job del cliente — ver *Gates de dependencias* abajo |
| ~~`frame.rs` — dos codificaciones para la misma trama~~ | Cerrado: `decode_frame` rechaza un `sender_token` que no venga ya en forma canónica — ver *Trama EC04* abajo |

## Trama EC04 — una sola codificación por trama (core, 2026-08-12)

Lo encontró la propiedad `fuzz::decode_frame_survives_any_bytes` al exigir que
`encode_frame(decode_frame(b)) == b`: `Token::parse` acepta mayúsculas y espacios y devuelve la
forma normalizada, así que `ec_D19B…` y `ec_d19b…` decodificaban a la **misma** trama desde bytes
distintos. Es la maleabilidad que se le quitó a las claves públicas en `0.8.1`, un piso más
arriba.

Hoy no es explotable: nada aguas abajo indexa por los bytes de la trama —el anti-replay usa el
`msg_id` sellado, no el frame— y desde `0.8.0` la trama entera viaja dentro del AEAD de sesión
(F-15), así que quien la escribe ya está autenticado. Se cerró igual porque el coste es un `if` y
el fallo que evita es el de F-10: alguien que más adelante haga caché, deduplique o firme por
bytes de trama hereda dos nombres para un mismo mensaje.

Cerrado en tres puntos, para que el codificador no pueda emitir bytes que su propio decodificador
rechaza: `WireFrame::new` normaliza al construir, `encode_frame` escribe la forma normalizada, y
`decode_frame` devuelve `InvalidFrame` si el token entrante no venía ya normalizado. No rompe el
wire: ningún emisor honesto —ni el core ni `wire_frame.dart`— produjo nunca un token en
mayúsculas. El caso mínimo quedó en `crates/core/proptest-regressions/fuzz.txt`.

**Cerrado también en Dart:** `WireFrame.decode` rechaza el token no canónico en vez de pasarlo a
minúsculas, y el constructor normaliza, así que las dos puntas hablan la misma forma y ningún
llamador puede emitir una trama que el core rechace.

## Gates de dependencias y de entrada malformada (CI, 2026-08-12)

| Gate | Cuándo | Bloquea |
| --- | --- | --- |
| Propiedades de entrada malformada | Cada push/PR, dentro de `cargo test` (~2 s) | Sí |
| Pasada profunda de las mismas propiedades (300k / 50k casos) | Cron nocturno | Sí (nocturno) |
| `cargo audit` | Cada push/PR + cron nocturno | Solo si el cambio toca un lockfile, o en el nocturno |
| `npm audit --audit-level=high` | Igual que `cargo audit` | Igual |
| `flutter analyze --no-fatal-infos` | Cada push/PR, en el job del cliente | Sí (errores y warnings) |

El criterio de bloqueo es el mismo en los dos audits: un advisory publicado esta noche sobre una
dependencia que el autor del PR no tocó no es su problema, y un rojo que nadie puede arreglar
enseña a ignorar los rojos. Si el diff toca `Cargo.lock` o `package-lock.json`, sí es su problema
y bloquea; si no, avisa y el nocturno se pone rojo delante de quien lleva la release.

## Cobertura

`messaging_service`, `call_service`, `local_database` y `relay_client` sumaban ~1.600 líneas sin
tests propios, y es exactamente donde viven F-3, F-4, F-6 y F-12.

Al cablear `ECS1` se cubrió parte: `test/sealed_relay_test.dart` (15 casos: ida y vuelta por
relay contra el core real, un código de error del core por caso, replay dentro y a través de un
reinicio, poda por ventana) y `test/call_block_test.dart` (6 casos sobre el derribo de llamada al
bloquear).

Del lado Rust, los cuatro fallos de esta auditoría los encontró una lectura, no un test, y el
último entró porque nada ejercitaba entrada malformada. `crates/core/src/fuzz.rs` (10 propiedades)
y `services/relay/tests/malformed.rs` (8) cubren ahora todo lo que decodifica bytes de un
desconocido —`ECS1`, `EH02`, `EC04`, PoP, y los cuerpos JSON y base64 del relay— con una sola
propiedad: nada de pánico, desbordamiento, asignación sin límite ni cuelgue. Los límites de
memoria se miden con un allocator instrumentado en `crates/core/tests/allocation.rs`. Cómo correr
la pasada profunda: [how-to-test.md](how-to-test.md).

El segundo pase añadió `test/stranger_policy_test.dart` (política de no-contactos, bandeja,
cuotas por remitente y de disco), `test/ffi_hygiene_test.dart` (los buffers se borran y las copias
que entran no se mutan) y `test/core_worker_test.dart` (las llamadas bloqueantes fuera del isolate
principal). Con eso F-6 queda cubierta. Sigue sin tests propios la ruta P2P de F-12, y los caminos
que dependen del plugin nativo de WebRTC solo se prueban con dobles.
