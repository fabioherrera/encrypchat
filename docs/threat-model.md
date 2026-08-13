# Modelo de amenazas — Encrypchat

**Última revisión:** 2026-08-12 · **Estado del producto:** pre-beta (F10)
**Estado de publicación:** publicable. Lo que bloqueaba este documento era describir dos
suplantaciones abiertas: F-1 y F-2 están cerradas de punta a punta —EH02 y `ECS1` en el core
(`0.8.0`), llamadas ya desde el cliente Flutter, con piso de ABI `0.8.0` para que un core viejo
no arranque en lugar de degradarse—, y las codificaciones alternativas de una clave pública, que
daban un segundo token, se rechazan en la puerta (`0.8.1`). Ver [audit-f10.md](audit-f10.md).

Este documento dice de qué protege Encrypchat, de qué no, y quién aprende qué. Está escrito
para que lo entienda alguien que no es criptógrafo, y para que un criptógrafo pueda
verificarlo contra el código. Si encontrás una diferencia entre lo que dice aquí y lo que hace
el código, el documento está mal: reportalo.

Un producto de privacidad que no publica sus límites está mintiendo por omisión. La sección
[Limitaciones conocidas](#7-limitaciones-conocidas-hoy) es la parte más importante.

## 1. Qué es Encrypchat, en una página

- Cada dispositivo es a la vez cliente y nodo. No hay servidor que guarde chats, media ni claves.
- La identidad es un par X25519 generado en el dispositivo. El **token** (`ec_` + 64 hex) es el
  hash SHA-256 de la clave pública. No hay registro, ni teléfono, ni email, ni cuenta.
- Los mensajes se cifran en origen con la clave pública del destinatario (X25519 efímero +
  ChaCha20-Poly1305) y viajan por TCP directo entre los dos dispositivos.
- Si el otro está desconectado, el mensaje ya cifrado puede quedar en un **relay ciego**: un
  buzón que guarda un blob opaco con TTL y lo borra cuando lo ha entregado —tras una segunda
  entrega de cortesía, o al vencer el TTL (§6.3)—.
- Las llamadas son WebRTC directo con DTLS-SRTP.

## 2. Qué protegemos

| Activo | Dónde vive | Cómo se protege |
| --- | --- | --- |
| Clave privada de identidad | Almacén seguro del SO (Keystore, Keychain, libsecret, DPAPI) | Nunca sale del dispositivo ni viaja por la red; no aparece en logs |
| Contenido de los mensajes | Dispositivos de origen y destino | Cifrado en origen; ni el relay ni la red ven el texto |
| Ficheros y fotos | Dispositivo | Cifrados en origen para el envío; sellados con AEAD en disco |
| Audio y vídeo | Entre los dos dispositivos | DTLS-SRTP, sin servidor de medios propio ni de terceros |
| Cuerpos de mensaje en reposo | Base de datos local | Fichero cifrado con SQLCipher (AES-256) y, encima, cada cuerpo sellado con AEAD; las dos claves salen del almacén seguro del SO |
| Autoría de un mensaje | En el propio criptograma | El remitente queda atado al contenido: prueba de posesión en el handshake P2P (EH02), sobre con remitente sellado en la ruta de relay (`ECS1`) |

## 3. De quién protegemos, y de quién no

### 3.1 Alguien en tu misma red

**No puede** leer el contenido de mensajes, ficheros ni llamadas: todo va cifrado antes de
salir del dispositivo.

**Sí puede** ver que dos IP intercambian tráfico, cuánto y cuándo; deducir cosas del tamaño por
encima de 512 bytes, que es donde el relleno deja de igualarlo todo (una foto no se confunde con
un mensaje corto, pero un mensaje corto tampoco se distingue de un acuse); cortarte la conexión;
y, si el relay está configurado sin TLS, leer tu token y el del destinatario en claro — la app
avisa de forma persistente cuando eso pasa.

**Ya no puede** hacerse pasar por vos con tu clave pública: el handshake exige probar posesión de
la privada y el sobre de relay ata al remitente con su contenido (§6.2, §6.3). Tampoco aprende
identidades escuchando, ni del handshake ni de las tramas de una sesión ya abierta (§6.2).

**Sí puede, y es el residual de esta sección:** abrir una conexión a tu puerto con una identidad
desechable y, completando el handshake, confirmar qué token está detrás de esa IP. Ver
[Limitaciones conocidas](#7-limitaciones-conocidas-hoy).

### 3.2 El operador del relay

El relay es opcional y solo interviene cuando el destinatario está desconectado. Guarda el
token del destinatario, un blob cifrado y una fecha de caducidad.

**No puede** leer el contenido: no tiene ninguna clave que lo permita y el diseño no contempla
dársela. Tampoco puede recuperar tu identidad desde el token, que es un hash.

**Sí puede** saber que alguien depositó un mensaje para `ec_abc…`, de qué tamaño y a qué hora;
ver la IP de quien deposita y la de quien recoge, y por tanto correlacionar "esta IP escribe a
este token" con "esta IP es dueña de este token"; retener blobs más de lo que promete o
registrar esa correlación, sin que puedas verificarlo desde fuera; y negarse a entregar.

**No confíes en el relay para el anonimato.** El relay ciego protege el *contenido*, no la
*relación*. Si tu adversario incluye a quien opera la infraestructura, usá solo conexión
directa, o poné Tor o una VPN por debajo.

### 3.3 Alguien con acceso físico al dispositivo

**Bloqueado**, con contraseña o biometría: la defensa principal es el cifrado del sistema
operativo, no la nuestra.

**Desbloqueado:** Encrypchat no te protege. Quien tenga la sesión abierta lee todo lo que vos
leés. No hay PIN de aplicación, ni bloqueo por inactividad, ni chats ocultos.

**Apagado, o con el disco sin cifrar:** el fichero de base de datos está cifrado con SQLCipher
bajo una clave derivada de la del almacén seguro, así que un portátil robado, un móvil apagado
o un backup recuperado no revelan con quién hablás, tus contactos, las fechas ni las rutas de
tus adjuntos. Lo que sí queda visible es el **listado** del directorio de media: el contenido
de cada fichero está sellado, pero cuántos hay, su tamaño y su fecha son metadatos del sistema
de ficheros. Cifrar el disco del dispositivo sigue siendo buena idea.

**Sobre desinstalar:** en iOS, Linux y Windows la clave privada **sobrevive** a desinstalar la
app, porque vive en el almacén del sistema y esas plataformas no lo limpian. Solo en Android
desaparece con la app. Para irte del todo está el **borrado de identidad** dentro de la app, que
quita la clave del llavero y después la base y los adjuntos; si se interrumpe, se reanuda en el
siguiente arranque antes de abrir nada. Lo que ese borrado no puede hacer es sobreescribir los
bytes: quedan como ciphertext sin clave, no como hueco en blanco, y un backup del sistema
anterior al borrado puede seguir teniendo la clave.

### 3.4 El proveedor de tu sistema operativo

Apple, Google, Microsoft y tu distribución están **por debajo** de Encrypchat: controlan el
teclado que escribe, la pantalla que muestra, el almacén donde vive la clave y la tienda desde
la que descargaste la app.

**No podemos protegerte de ellos y no vamos a decir lo contrario.** Lo que sí hacemos: no
mandar nada a sus servicios que no haga falta, no usar push (no hay notificaciones push,
precisamente por eso), y no incluir analítica, SDK de terceros ni crash reporting con
contenido.

Excepción explícita: las llamadas usan servidores **STUN públicos de Google** para descubrir
tu IP pública.

### 3.5 Un atacante con recursos de estado

**No puede**, hasta donde sabemos hoy, romper X25519 ni ChaCha20-Poly1305, ni leer contenido
capturado de la red.

**Sí puede** ver tráfico a escala nacional y correlacionar quién habla con quién por tiempos y
tamaños sin leer nada; comprometer un dispositivo con un exploit del SO, y ahí se acabó todo;
intervenir o presionar a quien opere un relay; y bloquear el acceso.

Encrypchat **no es una herramienta de anonimato ni de resistencia a la censura**. Protege el
contenido y elimina el servidor central de contenido; no oculta que lo usás ni con quién.

### 3.6 La persona del otro lado

El adversario más frecuente en la vida real es alguien con quien ya hablaste.

**No puede** leer tus conversaciones con terceros.

**Sí puede** guardar, capturar y reenviar todo lo que le mandes: el cifrado no impide una
captura de pantalla ni una foto con otro teléfono. Puede crear una identidad nueva en segundos
si la bloqueás, porque los tokens no cuestan nada y no hay directorio central. Tiene tu clave
pública, porque te tiene guardado, pero eso ya no le sirve para presentarse como vos ante nadie.

**Bloquear** corta la entrega de mensajes, fotos y llamadas de ese token en dos capas: la app
descarta el paquete antes de descifrarlo y el núcleo se niega a abrir o mantener sesión. Se
aplica contra la identidad autenticada del remitente, no contra un campo que él elija, así que
no se evade suplantando a otro contacto. Tampoco se evade reescribiendo la misma clave de otra
forma: una clave pública tiene una sola codificación válida y las demás se rechazan al entrar
(§6.1), que era la vía por la que un bloqueado volvía con un token nuevo sin cambiar de clave.
Si hay una llamada en curso con ese token, se corta antes de aplicar el bloqueo. No se le avisa,
y no impide que vuelva con otra identidad.

El bloqueo es **local y unilateral**: este dispositivo deja de aceptar, pero la otra parte puede
seguir depositando en un buzón de relay que ya nadie vacía, hasta que caduque por TTL.

**Un desconocido** —alguien que tiene tu token pero no está en tus contactos— no entra en tus
chats: cae en una bandeja de solicitudes con techo, solo texto, sin sonido y sin poder dejarte
ficheros en el disco (sección 7). Aceptarlo es un acto explícito tuyo.

## 4. Fuera de alcance, por diseño

No son fallos pendientes: son cosas que Encrypchat **no intenta hacer**.

- **Anonimato de red.** Tu IP es visible para tu par y para el relay. Sin enrutado cebolla ni
  mixnet.
- **Ocultar que usás Encrypchat.** El protocolo no está ofuscado ni imita otro tráfico.
- **Protegerte de tu propio dispositivo.** Malware, teclados maliciosos o alguien mirando por
  encima del hombro quedan fuera.
- **Impedir capturas de pantalla del otro lado.** Ningún sistema E2EE puede.
- **Moderación de contenido.** No hay servidor que pueda leer nada. El reporte de abuso genera
  un informe **local** que vos decidís qué hacer con él; nadie lo recibe automáticamente.
- **Recuperación de cuenta.** Si perdés la clave privada, perdiste la identidad. Tener reseteo
  significaría que alguien más puede tomarla.
- **Sincronización entre dispositivos.** Una identidad vive en un dispositivo; el historial no
  se sincroniza.
- **Confidencialidad hacia adelante por mensaje.** No hay ratchet, y el matiz importa según por
  dónde vaya el mensaje. En una **sesión P2P** sí hay confidencialidad hacia adelante **por
  sesión**: la clave de transporte sale de un DH entre las dos efímeras del handshake, que se
  destruyen al terminarlo, así que quien haya grabado el tráfico y después consiga las **dos**
  claves de identidad no puede descifrar esa conversación. Lo que no hay es granularidad por
  mensaje: quien consiga la clave de una sesión —arrancándola de la memoria de un dispositivo
  mientras está viva— lee esa sesión entera. En la **ruta de relay** no hay confidencialidad
  hacia adelante en absoluto: el blob se cierra contra tu clave estática —la efímera del emisor
  es de un solo blob, pero tu clave permanente entra en las dos derivaciones—, de modo que quien
  obtenga tu clave privada y tenga blobs guardados los lee.
- **Metadatos de red.** Ver sección 5. No prometemos "cero metadatos" y no lo vamos a hacer
  mientras haya red de por medio.

## 5. Metadatos: quién aprende qué

| Actor | Aprende | No aprende |
| --- | --- | --- |
| Observador de red (Wi-Fi, ISP) | Que tu IP habla con otra IP; volumen, horarios, y el tamaño de cada mensaje por encima de 512 bytes; que es tráfico de Encrypchat, por los primeros bytes del handshake | Contenido de los mensajes; identidades, ni en el handshake ni en las tramas de una sesión ya establecida, que van cifradas de punta a punta del socket (F-15); la diferencia entre un ACK y un mensaje corto; tokens en la ruta de relay si el relay usa TLS |
| Operador del relay | Token del destinatario, tamaño del blob, hora de depósito y recogida, IP de ambas puntas | Contenido, token del remitente, nombres de fichero |
| STUN público de Google | Tu IP pública y el momento de iniciar o recibir una llamada | Con quién hablás, qué decís, tu token |
| Tu par | Tu token, tu clave pública, tu IP durante la conexión, todo lo que le enviás | Tus otras conversaciones |
| Encrypchat (nosotros) | **Nada.** No operamos servidores de contenido, no hay telemetría ni analítica | — |
| Quien tenga tu dispositivo desbloqueado | Todo | — |

Notas honestas sobre esa tabla:

- **El relay ve el token del destinatario.** Es inevitable: sin él no sabe a qué buzón dejar el
  blob. Por eso es opcional y por eso preferimos siempre la conexión directa.
- **El STUN de Google ve tu IP al llamar.** Es un tercero que no controlamos. Está ahí porque
  sin él las llamadas no atraviesan la mayoría de los NAT domésticos. Si eso no te sirve, no
  uses llamadas.
- **La correlación es el ataque realista.** Nadie va a romper ChaCha20; van a mirar quién habló
  con quién y cuándo.

## 6. Superficies, una por una

### 6.1 Identidad y token

Par X25519 del CSPRNG del sistema. `token = "ec_" + hex(SHA-256(pubkey))`. La privada vive en
el almacén seguro del SO. La tarjeta de contacto que compartís
(`encrypchat:contact:v1:<token>:<pubkey>:<nombre>`) **incluye tu clave pública en claro**: es
pública por diseño, porque quien te escribe la necesita.

El token no autentica por sí mismo: es un identificador, no una credencial. Un token que llega
por un canal que alguien controla puede ser el de esa persona. Verificá por un canal aparte.

**Una clave, un token.** Que el token sea un nombre estable para un par exige que cada clave
tenga una sola codificación, y X25519 no lo regala: la curva ignora el bit alto y reduce módulo
`p`, así que varias cadenas de 32 bytes son la misma clave para un Diffie-Hellman y claves
distintas para un hash. Toda clave pública que entra —tarjeta de contacto, QR, wire, FFI— se
rechaza si no viene en su forma reducida. Sin ese control, un bloqueado volvía con la misma clave
escrita de otra manera y un token limpio.

**Falta:** números de seguridad comparables dentro de la app y aviso cuando cambia la clave de
un contacto.

### 6.2 Canal P2P y handshake EH02

TCP directo con tramas de longitud prefijada. Al conectar corre **EH02**, cuatro mensajes con
autenticación mutua:

1. quien llama envía magia, versión y un nonce — sin identidad;
2. quien escucha responde con una clave efímera de un solo uso y otro nonce — **sin identidad**;
3. quien llama prueba su identidad sellándola contra esa efímera;
4. quien escucha, sabiendo ya con quién habla, prueba la suya sellándola contra la clave del otro.

Las dos pruebas usan el mismo primitivo de doble Diffie-Hellman que los blobs de relay
(`ECS1`, §6.3): abrirlas exige un DH que solo puede calcular el verificador, y eso no se hace
con la clave pública de la víctima. El detalle importa, porque las dos no son simétricas. La
prueba del mensaje 4 va contra la clave **estática** del iniciador, que en ese punto ya se
conoce. La del mensaje 3 va contra la **efímera** del que escucha, porque quien llama todavía no
sabe con quién habla: de ahí se sigue que quien conteste el socket abre el mensaje 3 y aprende
el token de quien llama **sin haber probado ninguna identidad**, sea el destinatario legítimo,
un impostor en esa dirección o un atacante activo en la ruta. Es la otra cara de §7.9. Cada
prueba va
atada por AAD a la versión, al rol, a los dos nonces y a la efímera de la sesión, así que no
sirve en otra conexión ni en el sentido contrario. Límites: 5 s de handshake, 32 conexiones sin
autenticar a la vez, 4 KiB de buffer pre-auth.

Esto **sustituye** a EH01, cuya prueba se podía construir con la clave pública del verificador
y por tanto no probaba nada (F-1). Los dos extremos tienen que actualizarse a la vez.

**Qué consigue en exposición de identidad:** quien escucha no emite nada identificable hasta
haber verificado a quien llama. Un observador pasivo de la red no aprende ninguna identidad del
handshake, y quien abre un TCP sin poder probar ninguna identidad no obtiene nada. Un par
bloqueado se rechaza entre los mensajes 3 y 4, así que tampoco llega a saber quién le respondió.

**Qué no consigue:** quien llama tiene que identificarse primero. No hay forma de probarle nada
a alguien cuya clave todavía no conocés, así que un atacante que genere una identidad
desechable y complete el handshake sí obtiene la identidad de quien escucha. Cerrarlo del todo
exige que quien llama conozca la clave pública del otro de antemano (patrón tipo Noise `IK`);
hoy el destino de un dial se indica por token, y el token es un hash del que no se recupera la
clave.

**Clave de sesión y transporte cifrado (F-15).** EH02 ya no solo autentica: cada extremo aporta
una clave efímera de un solo uso, y de ellas sale la clave de sesión que cifra **todo** el
transporte, cabecera incluida. Antes la cabecera `EC04` viajaba en claro —solo el payload era
E2EE—, así que quien esnifara la wifi leía el `sender_token` de cada trama y podía dibujar el
grafo social sin descifrar nada. Ahora un observador ve un prefijo de longitud y bytes opacos.

Hay **una clave por sentido**, y el nonce es un contador implícito que nunca viaja: el receptor
solo prueba el siguiente. Una trama repetida, reordenada, borrada o inyectada dentro de una
sesión no descifra, y la sesión se cierra. Dentro de una sesión el flujo es exactamente-una-vez
y en orden, o se corta.

**Lo que sigue viéndose:** el tamaño. Todo lo que quepa en 512 bytes de texto plano sale con el
mismo tamaño —un ACK, un "ok" y un párrafo corto son indistinguibles—, pero por encima de ahí la
longitud es la del mensaje y una foto se distingue de un texto. Rellenar más no compensa: no
esconde el volumen ni los tiempos, y el observador ya sabe qué IP habla con qué IP, que es el
dato caro. Se declara como límite, no se disimula. También se ve que el tráfico es de
Encrypchat: el primer mensaje del handshake empieza por `EH02`.

### 6.3 Relay ciego y prueba de posesión

Tres operaciones: depositar, pedir desafío y recoger. Recoger exige una prueba de posesión: el
relay genera un par efímero y un nonce, y solo entrega el buzón a quien demuestre con un ECDH
que es dueño del token. El desafío es de un solo uso, caduca en 2 minutos y **no lleva
destinatario**: pedirlo no dice a qué buzón apunta nadie, y se identifica por un id opaco, de
modo que un tercero no puede pisar el desafío de otra persona y dejar su buzón sin vaciar. Se
consume solo si la prueba verifica.

Los blobs tienen TTL (24 h por defecto, 7 días máximo). Al entregarse no se borran: quedan **en
lease** 60 s, escondidos incluso de su destinatario, y se entregan una segunda y última vez si el
cliente vuelve después. Así un cliente al que el sistema operativo mata entre el `200` y su propio
guardado no pierde el mensaje. Hay cuota por buzón (8 MiB), techo global de disco y límite por IP.
Los logs no registran el token de destino.

El sobre (`ECS1`) ata al remitente con su contenido: la clave que abre el cuerpo se deriva de la
clave permanente del emisor contra la tuya, así que producir un blob que abra bien exige tener esa
clave privada, y no hay un campo de remitente aparte que se pueda cambiar de sitio. Ese
control tiene una propiedad deliberada: **solo vos podés comprobarlo**. La prueba no es
transferible a un tercero —cualquiera con tu clave privada podría haber fabricado el mismo
blob—, y eso es a propósito: una firma pública convertiría cada mensaje en un recibo de quién te
escribió. Sirve para atribuir y para bloquear; no sirve como prueba ante nadie más.

Dos precisiones para que eso no se lea como más de lo que es. La negabilidad es criptográfica y
va contra el **blob**: no va contra tu testimonio acompañado de indicios, y las horas, las IP y
la correlación en el relay siguen existiendo (§3.2). Y es negabilidad frente a terceros, no
frente al destinatario: para él la atribución es fuerte, que es justo lo que hace que el bloqueo
funcione.

Lo que **no** da: el depósito no está autenticado, y el TLS es responsabilidad de quien opere el
relay. La entrega es **al menos una vez, dos como máximo**: si el cliente muere en los dos
intentos el mensaje se pierde igual, y el precio de los dos intentos es que cada blob del relay
cruza la red dos veces (la copia repetida la descarta el cliente por `msg_id`).

### 6.4 Llamadas

La señalización viaja **solo** por el canal P2P, cifrada como cualquier mensaje, nunca por el
relay. El medio va punto a punto con DTLS-SRTP. No hay SFU, ni TURN, ni servidor de medios: el
audio y el vídeo nunca pasan por infraestructura nuestra. Sin TURN, algunas combinaciones de
NAT no conectan; preferimos que la llamada falle a montar un servidor por el que pase tu voz.

Micrófono y cámara se piden al aceptar, no al sonar. Una invitación de un token que no está en
contactos se descarta sin sonar.

### 6.5 Almacenamiento local

SQLite en el directorio privado de la app, **cifrado como fichero con SQLCipher** bajo una
clave derivada de la del almacén seguro (`HMAC-SHA256(db_key, …)`, para no reutilizar los
mismos bytes en dos primitivas). Encima de eso, los cuerpos de mensaje y los ficheros van
sellados con ChaCha20-Poly1305 bajo `db_key`: son dos capas distintas, y la de dentro sigue
protegiendo si alguna vez se abre la base. En Android, `allowBackup=false`.

Lo que el cifrado de fichero **no** cubre: un dispositivo desbloqueado con el llavero
accesible —quien lee la clave abre la base, y ahí la frontera es la pantalla de bloqueo del
sistema— y el listado del directorio `media/`, cuyo contenido está sellado pero cuyo número de
ficheros, tamaños y fechas son metadatos del sistema de ficheros.

Si el llavero pierde la clave, el historial se pierde: la app lo dice en pantalla en vez de
empezar una base nueva encima.

El disco no es infinito y el que lo llena es el otro lado, así que los adjuntos entrantes tienen
techo: 512 MiB por par y 2 GiB en total, comprobado antes de escribir el fichero. Pasado el
techo el adjunto se rechaza y la app te lo dice, en vez de crecer hasta que el sistema se queje.
Un desconocido no llega ni a esa cuenta: la bandeja de solicitudes no acepta ficheros.

### 6.6 La frontera FFI

Criptografía, identidad y nodo P2P en Rust; interfaz en Flutter. Cada símbolo de la frontera —21
en la versión de arriba— tiene contrato escrito ([ffi-contract.md](ffi-contract.md)): qué
punteros deben ser válidos, quién libera qué, qué se escribe en error (nada) y cuánto bloquea
cada llamada. Los puntos de entrada capturan pánicos y los convierten en código de error.

Material sensible que cruza: la clave de identidad y la de la base de datos. Rust limpia sus
copias y **el puente Dart ya limpia las suyas**: todo buffer nativo que llevó una clave o un
texto plano se pone a cero antes de liberarse, incluidos los que reserva el propio core y se
devuelven al llamante (F-10 de [audit-f10.md](audit-f10.md)). Queda un residuo que el lenguaje
no permite cerrar: la copia que vive en el heap de Dart —el `Uint8List` de la clave de identidad
mientras hay sesión, y el `String` en base64 que devuelve el almacén seguro al cargarla— la
gestiona el recolector, que puede haberla movido o duplicado. Cerrar eso significaría que la
clave no cruce la frontera en cada mensaje, sino que el descifrado ocurra dentro del núcleo con
la copia que el nodo ya tiene; es un cambio de superficie FFI, no del cliente.

Las llamadas de nodo con presupuesto de bloqueo (enviar, 15 s; marcar, 10 s) corren en un
isolate aparte, así que un par que acepta la conexión y no contesta no congela la interfaz
(F-11). El handle del nodo se comparte por dirección entre los dos isolates, que es lo que el
contrato permite; pararlo va por la misma cola que los envíos, para que nunca se libere con una
llamada dentro.

## 7. Limitaciones conocidas hoy

Estado real del código en la fecha de arriba. Se actualiza cuando cambia, no cuando conviene.
El detalle técnico está en [audit-f10.md](audit-f10.md).

1. **La autoría la dan el transporte y el sobre, no el cifrado en sí.** El handshake P2P sí
   prueba posesión de la clave privada (EH02, §6.2) y los blobs de relay sí atan al remitente
   (`ECS1`, §6.3): las dos suplantaciones descritas en versiones anteriores de este documento
   están cerradas en el core y en el cliente, que es el que las tiene que llamar para que estén
   en vigor. Lo que sigue siendo cierto es que `encrypchat_encrypt` por sí solo no dice quién
   escribió —cualquiera con tu clave pública puede producir algo que descifra bien—, así que cada
   ruta nueva que se añada tiene que autenticar explícitamente por uno de los dos caminos: la capa
   cripto no lo hace sola (F-2). Y la atribución que obtenés vale para vos, no ante un tercero:
   es deliberadamente no transferible (§6.3).
2. **Un blob de relay reencolado ya no se muestra dos veces, pero sí puede llegar tarde.** El
   cliente recuerda los `msg_id` de `ECS1` que abrió y descarta el repetido; la tabla se poda
   con la propia ventana de frescura, así que no crece sin límite. Lo que el `msg_id` no dice es
   *cuándo* correspondía: un sobre auténtico capturado y depositado más tarde, dentro de la
   ventana de 7 días, es nuevo para un dispositivo que nunca lo vio y se mostrará con su fecha
   original. Por eso la señalización de llamadas sigue sin salir por el relay: un timbre no
   molesta por repetido, molesta por llegar a las 4 de la madrugada del viernes.
3. **Bloquear no detiene a quien use una identidad nueva.** El bloqueo se aplica siempre contra
   una identidad que el emisor no elige —probada por el handshake en P2P, sacada del criptograma
   en relay—, y corta la llamada en curso antes de aplicarse. Lo que nadie puede impedir es que
   la misma persona genere otro token y vuelva.
4. **Un desconocido puede escribirte, con techo.** Quien tenga tu token entra en la bandeja de
   solicitudes: solo texto, hasta 5 mensajes de 4 KiB por remitente y 20 remitentes a la vez,
   sin notificación y sin adjuntos ni llamadas. Todo lo que exceda eso se descarta antes de
   tocar el disco —y, si no sos contacto, antes incluso de descifrarlo—, así que el coste máximo
   de todos los desconocidos juntos son 400 KiB de texto y el ruido de tener que mirar la
   bandeja. Cuando los 20 huecos están ocupados, la solicitud más antigua se desaloja para dejar
   sitio a la nueva: es una ventana rodante, no una cola que se cierra. La consecuencia es que
   veinte identidades desechables —que no cuestan nada— pueden empujar fuera una solicitud que
   no llegaste a leer, aunque no pueden dejarte incomunicado de forma indefinida. Tampoco hay
   forma de saber si el token te llegó de quien creés.
5. **Alguien puede llenarte el buzón del relay, y en silencio.** Depositar no exige
   autenticarse —hace falta para que cualquiera pueda escribirte estando vos desconectado—, así
   que quien conozca tu token puede ocupar tu cuota y hacer que los mensajes que te manden
   mientras tanto se pierdan. El relay responde a todos igual, aceptado o descartado, y esa
   opacidad es deliberada: distinguirlos convertía al relay en un delator de tu presencia, y
   avisar al remitente honesto es la misma petición que avisar a quien te está inundando. El
   precio es que ni él ni vos os enteráis. Los mensajes por conexión directa no se ven
   afectados, y el buzón se libera según caducan los blobs por TTL.
6. **El almacenamiento de adjuntos tiene tope y se llena.** 512 MiB por contacto y 2 GiB en
   total: un contacto que insista verá sus envíos rechazados en vez de llenarte el disco, pero
   el rechazo es silencioso para él y visible para vos como aviso de cuota. Borrar la
   conversación libera el espacio; no hay purga automática por antigüedad.
7. **El listado del directorio de media es visible** aunque el contenido esté sellado y la
   base de datos cifrada: cuántos adjuntos tenés, de qué tamaño y de qué fecha.
8. **La clave privada sobrevive a desinstalar** en iOS, Linux y Windows: vive en el almacén del
   sistema y esas plataformas no lo limpian. Para irte del todo usá el borrado de identidad de
   la app, que sí quita la clave del llavero; desinstalar por su cuenta no basta.
9. **Quien llama se identifica primero.** Al abrir una conexión P2P, quien contesta no revela
   nada hasta haber verificado a la otra parte, pero la otra parte sí tiene que revelarse antes.
   Es una propiedad del patrón de handshake, no un descuido: no se le puede probar nada a una
   clave que todavía no conocés. Consecuencia práctica: alguien que genere una identidad
   desechable y complete el handshake confirma qué token está detrás de esa IP. Cerrarlo exige
   marcar con la clave pública del destino en lugar de con su token (§6.2).
10. **El límite de peticiones del relay depende de la configuración del operador.** El relay ya
   sabe cobrar el límite a la IP real detrás de un proxy inverso, pero solo si el operador le
   dice de qué proxies fiarse; sin esa lista ignora la cabecera y cobra a la dirección que
   conecta, que detrás de un proxy es una sola para todos. Hay techo global de disco (1 GiB por
   defecto, que rechaza en vez de desalojar nada ya aceptado). Sin defensa contra inundación
   distribuida: un flood no lee mensajes ajenos, pero deja el relay inútil para los nuevos.
11. **El informe de abuso sale de la app, y dónde acaba depende de la plataforma.** Ya no pasa
   por el portapapeles: el camino por defecto escribe un archivo, y en Linux y Windows elegís
   vos la ruta. En Android e iOS el diálogo de guardado no existe, así que el archivo cae en
   una carpeta de la propia app —visible desde Archivos en iOS, legible por USB en Android—, y
   eso lo pone al alcance de cualquiera que tenga el teléfono desbloqueado, que es una
   situación realista para quien está denunciando a alguien cercano. Esa carpeta sí entra en
   el borrado de identidad —un informe en claro con tu token no sobrevive a la identidad que
   nombra—; un archivo que guardaste en otra ruta queda fuera de nuestro alcance. Copiar al
   portapapeles
   sigue disponible como segunda acción, con lo que eso implica dicho antes de pulsarla: en
   escritorio puede sincronizarse a la nube y en Android pueden leer otras apps. En los dos
   casos el informe se genera local y no se envía a nadie; lo que cambia es cuánta gente puede
   verlo después.
12. **Un par que abre una sesión te puede hacer trabajar.** Completar el handshake con una
   identidad propia no cuesta nada, y desde ahí lo que ese par mande te cuesta CPU y batería:
   descifrarlo para poder decidir si vale. La memoria ya no: lo que puede dejarte residente está
   acotado en bytes —32 MiB por conexión y 64 MiB en total, se llegue por una sesión o por mil—,
   y quien se pasa recibe contrapresión primero y se queda sin conexión después, sin arrastrar a
   las demás. Lo que sigue sin techo es el trabajo: tramas pequeñas que se descifran y se
   descartan una tras otra, y una interfaz que procesa lo entrante antes de poder rechazarlo. Es
   un problema de disponibilidad contra tu propio dispositivo, no de confidencialidad: nadie lee
   nada por esta vía. La parte de trabajo sigue pendiente antes de 1.0.
13. **Sin verificación de contactos en la app**: ni números de seguridad ni aviso de cambio de
   clave.
14. **Sin protección contra capturas de pantalla** en ninguna plataforma.
15. **Sin confidencialidad hacia adelante por mensaje.**

## 8. Reportar una vulnerabilidad

**info@elnerd.com** — buzón atendido por el operador. Es una dirección de otro dominio, así que
está confirmada desde el propio producto en
[encrypchat.com/es/security#reportar](https://encrypchat.com/es/security#reportar) —la versión
web de este documento, y el destino del campo `Policy:`—, en
[encrypchat.com/es/privacy#seguridad](https://encrypchat.com/es/privacy#seguridad) y en
[`/.well-known/security.txt`](https://encrypchat.com/.well-known/security.txt); si la
encontraste en cualquier otro sitio, comprobala contra una de esas tres. Todavía no hay clave
pública para reportes cifrados; si la necesitás, pedila en un primer correo sin detalles.

Que esas tres fuentes sigan diciendo lo mismo, y que el `security.txt` no esté caducado, no
depende de que alguien se acuerde: `scripts/check-security-txt.sh` corre en cada build y en la
pasada nocturna, y falla un mes antes de la fecha o en cuanto una de las copias se desvía. Un
buzón de seguridad que dejó de existir es peor que no publicar ninguno, porque el que encuentra
el fallo cree que avisó.

Pedimos divulgación coordinada: contanos qué encontraste y dejanos un plazo razonable para
corregirlo antes de publicarlo. No hay programa de recompensas. Sí publicamos los hallazgos y
su estado en `docs/`, incluidos los que no hemos cerrado.
