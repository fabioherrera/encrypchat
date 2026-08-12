import type { Dictionary } from "./types";

const es: Dictionary = {
  meta: {
    titleDefault: "Encrypchat — chat P2P cifrado, zero-cloud",
    titleTemplate: "%s · Encrypchat",
    description:
      "Encrypchat es un mensajero cifrado de igual a igual. Chats y medios permanecen en tu dispositivo. Los relays ciegos opcionales solo guardan cifrado hasta la entrega.",
    keywords: [
      "Encrypchat",
      "chat cifrado",
      "mensajería P2P",
      "zero-cloud",
      "E2EE",
      "chat descentralizado",
    ],
    ogLocale: "es_ES",
  },
  nav: {
    features: "Funciones",
    download: "Descargar",
    faq: "FAQ",
    cta: "Obtener la app",
    primaryAria: "Principal",
    langSwitcherAria: "Idioma",
  },
  footer: {
    note: "Mensajería P2P cifrada de extremo a extremo. Los relays ciegos opcionales solo almacenan cifrado hasta la entrega — no tus chats legibles.",
    privacy: "Privacidad",
    terms: "Términos",
    faq: "FAQ",
    download: "Descargar",
    aria: "Pie de página",
  },
  platforms: {
    android: "Android",
    ios: "iOS",
    linux: "Linux (Fedora)",
    windows: "Windows",
    comingSoon: "Próximamente",
  },
  home: {
    heroAria: "Hero",
    lead: "Chat cifrado de igual a igual en tu dispositivo — no un buzón en la nube que podamos leer.",
    ctaDownload: "Descargar",
    ctaFeatures: "Cómo funciona",
    privacyTitle: "Privacidad en el dispositivo",
    privacyP1:
      "Cada instalación es cliente y nodo local. La identidad es un token criptográfico que compartís (QR o pegar) — no un directorio telefónico que controlemos. Si alguien está offline, un relay ciego opcional puede guardar cifrado sellado hasta que se reconecte; los relays no pueden leer el contenido.",
    privacyP2Before: "En la app verás",
    privacyP2P2p: "P2P",
    privacyP2Mid: "cuando los pares se conectan en directo,",
    privacyP2Relay: "relé",
    privacyP2After:
      "cuando el cifrado sellado espera offline, y offline cuando el dispositivo no alcanza la red.",
    platformsTitle: "Plataformas",
    softwareDescription:
      "Mensajero cifrado de igual a igual. Los mensajes permanecen en tus dispositivos; los relays ciegos opcionales solo guardan cifrado.",
  },
  features: {
    metaTitle: "Funciones",
    metaDescription:
      "Mensajería P2P cifrada, almacenamiento en el dispositivo, tokens criptográficos y relays ciegos opcionales en Encrypchat.",
    h1: "Funciones",
    intro: "Encrypchat está pensado para que los chats legibles nunca vivan en nuestra nube.",
    e2eeTitle: "Cifrado de extremo a extremo",
    e2eeBody:
      "Los mensajes se cifran en tu dispositivo con la clave del destinatario antes de salir. Solo el dispositivo previsto puede descifrarlos.",
    p2pTitle: "Primero peer-to-peer",
    p2pBody:
      "Cuando ambos están online, el tráfico prioriza un camino directo entre dispositivos. Eso reduce intermediarios en chat en vivo, medios y llamadas.",
    zeroCloudTitle: "Zero-cloud de contenido",
    zeroCloudBody:
      "El historial y los medios se guardan en tu teléfono o computadora, en una base de datos cifrada con SQLCipher y con los cuerpos sellados encima. No operamos un buzón de mensajes que pueda leer tus conversaciones.",
    relayTitle: "Relay ciego (opcional, offline)",
    relayBodyBefore: "Si el destinatario está offline, un relay puede guardar temporalmente",
    relayCiphertext: "cifrado",
    relayBodyAfter:
      "dirigido a su token y borrarlo tras la entrega. Los relays no son una copia en la nube de tu historial y no pueden descifrar el contenido.",
    tokenTitle: "Identidad por token",
    tokenBody:
      "Los contactos son tokens criptográficos (de claves públicas), intercambiados por QR o pegado. No hay un directorio telefónico central como fuente de verdad.",
    cta: "Obtener Encrypchat",
  },
  download: {
    metaTitle: "Descargar",
    metaDescription:
      "Apps nativas Encrypchat para Android, iOS, Linux y Windows. Builds de prueba en GitHub Releases o dist/ local; ver docs/phase-8.md.",
    h1: "Descargar",
    intro:
      "Apps nativas para Android, iOS, Linux (Fedora) y Windows. Los instaladores públicos irán a GitHub Releases cuando se publiquen — no enlazamos URLs que aún no existen.",
    sourceNote:
      "Builds de prueba: ver docs/phase-8.md en el repositorio (make package → dist/ para tarball Linux y APK Android). iOS y Windows siguen necesitando host Mac / Windows.",
  },
  faq: {
    metaTitle: "FAQ",
    metaDescription:
      "Preguntas frecuentes sobre Encrypchat: cifrado P2P, almacenamiento zero-cloud, relays ciegos, permisos del dispositivo y plataformas.",
    h1: "FAQ",
    items: [
      {
        q: "¿Encrypchat está cifrado de extremo a extremo?",
        a: "Sí. Los mensajes se cifran en el dispositivo del emisor con la clave del destinatario. El texto legible debe existir solo en los extremos.",
      },
      {
        q: "¿Guardan mis chats en la nube?",
        a: "No. El contenido del chat se almacena en tus dispositivos. Eso es lo que llamamos zero-cloud de contenido.",
      },
      {
        q: "¿Qué es un relay ciego?",
        a: "Un ayudante opcional para entrega offline. Puede guardar cifrado sellado para tu token hasta que vuelvas online y luego borrarlo. No puede descifrar el contenido.",
      },
      {
        q: "¿Qué plataformas soportan?",
        a: "Android, iOS, Linux (Fedora) y Windows son objetivos de primera clase. Paquetes de prueba Linux/Android en dist/ (ver docs/phase-8.md); tiendas y GitHub Releases cuando empiece la publicación.",
      },
      {
        q: "¿Cómo agrego un contacto?",
        a: "Intercambiás tokens criptográficos (por ejemplo con QR). No hay un directorio telefónico central como fuente de verdad.",
      },
      {
        q: "¿Puede escribirme alguien que no es mi contacto?",
        a: "Sí, si tiene tu token, pero no entra en tus chats: cae en una bandeja de solicitudes acotada. Solo texto, hasta 5 mensajes de 4 KiB por remitente y 20 remitentes a la vez, sin adjuntos, sin llamadas y sin notificación. Aceptar la solicitud es lo que crea el contacto; también podés descartarla o bloquear el token.",
      },
      {
        q: "¿Qué ve exactamente un relay ciego?",
        a: "El token de destino, el tamaño del sobre cifrado, las marcas de tiempo, el TTL y la IP desde la que te conectás. Nunca el contenido ni tus claves. El sobre se borra tras la entrega o al expirar el TTL, y el relay solo entra en juego si lo configurás.",
      },
      {
        q: "¿Las llamadas pasan por sus servidores?",
        a: "No. El audio y el vídeo van directos entre los dos dispositivos con cifrado DTLS-SRTP; no hay SFU ni servidor de media de Encrypchat. Para establecer la conexión se usan servidores STUN públicos de Google, que ven tu dirección IP y el momento de la llamada, no su contenido.",
      },
      {
        q: "¿Están cifrados mis datos dentro del dispositivo?",
        a: "Sí, en dos capas. El fichero de base de datos está cifrado por completo con SQLCipher (AES-256) bajo una clave derivada de la que guarda el almacén seguro del sistema operativo, y encima el cuerpo de cada mensaje y cada fichero de media van sellados con cifrado autenticado. Eso protege el fichero cuando alguien lo lee desde el disco: portátil robado, móvil apagado, backup recuperado u otra cuenta del mismo sistema. Lo que no protege es un dispositivo desbloqueado con el llavero accesible —quien lee la clave abre la base, y esa frontera la pone la pantalla de bloqueo del sistema, no nuestra capa de cifrado— ni el listado del directorio de media: el contenido de cada fichero está sellado, pero cuántos hay, su tamaño y su fecha son metadatos del sistema de ficheros.",
      },
      {
        q: "¿La app necesita acceso a mis fotos?",
        a: "En Android no: no se pide permiso de galería. Al adjuntar, el selector de fotos del sistema nos entrega solo la imagen que elegís, y en un dispositivo antiguo sin ese selector se abre el explorador de ficheros, que tampoco pide permiso. En iOS, el sistema puede pedirte acceso a la fototeca al elegir la foto. En Linux y Windows se usa el diálogo de ficheros del sistema. La foto se cifra en tu dispositivo antes de salir.",
      },
      {
        q: "¿Cómo borro mi identidad y mis datos?",
        a: "Desinstalando la app: con ella se van la base de datos local y los ficheros de media. La clave privada solo desaparece junto con la app en Android; en iOS, Linux y Windows queda en el llavero del sistema y hay que borrar esa entrada a mano. Dentro de la app todavía no hay una acción de «borrar identidad».",
      },
      {
        q: "¿Usan analítica o publicidad?",
        a: "No. La app no incluye SDK de métricas, crash reporting ni identificadores de publicidad, y encrypchat.com no usa cookies propias ni analítica.",
      },
    ],
  },
  legal: {
    relatedAria: "Páginas relacionadas",
  },
  privacy: {
    metaTitle: "Política de privacidad",
    metaDescription:
      "Qué datos existen en Encrypchat y dónde viven: chats en tu dispositivo, en base de datos cifrada. Relay ciego opcional, llamadas P2P, sin cuentas ni analítica.",
    h1: "Política de privacidad",
    updated: "Última actualización: 12 de agosto de 2026 · versión 1.0 (previa a revisión legal)",
    updatedIso: "2026-08-12",
    summary:
      "Encrypchat no tiene cuentas, no guarda tus conversaciones en la nube y no usa analítica ni publicidad. Tu clave privada, tus chats y tu media viven en tu dispositivo. Lo único que puede tocar un servidor es material cifrado que no podemos leer: el sobre que un relay ciego opcional guarda hasta la entrega, y los servidores STUN públicos que ayudan a montar una llamada y ven direcciones IP.",
    disclaimer:
      "Este documento describe el comportamiento real del software en su estado actual (pre-1.0). No es asesoría legal, todavía no lo ha revisado un abogado y hay campos pendientes de completar por el operador. Debe cerrarse antes de publicar en Google Play o la App Store.",
    sections: [
      {
        id: "responsable",
        title: "Quién publica esta política",
        blocks: [
          "Encrypchat es un proyecto de software en desarrollo. La entidad legal responsable del tratamiento, su domicilio y su punto de contacto están pendientes de designación.",
          "Mientras ese apartado siga pendiente, este texto sirve como declaración técnica honesta de lo que hace el software, no como política definitiva para una tienda de aplicaciones.",
        ],
      },
      {
        id: "datos",
        title: "Qué datos existen y dónde viven",
        blocks: [
          "Todo lo siguiente se crea y se queda en tu dispositivo. No hay copia en servidores nuestros.",
          [
            "Identidad: un par de claves X25519 generado localmente. La clave privada se guarda en el almacén seguro del sistema operativo: en Android, cifrada con una clave del Keystore dentro del directorio de datos de la app; en iOS en el Keychain; en Linux en el llavero libsecret y en Windows en el Administrador de credenciales. La clave pública produce tu token público «ec_…», que es lo único que compartís.",
            "Chats: se guardan en una base de datos local dentro del directorio privado de la app. El cuerpo de cada mensaje está sellado con cifrado autenticado usando una clave que vive en el almacén seguro del SO.",
            "Media: las fotos enviadas y recibidas se guardan cifradas como ficheros sellados en el almacenamiento privado de la app; no quedan bytes de la foto en claro en disco. En móvil, la copia temporal que crea el selector del sistema se borra en cuanto la foto queda sellada, y al arrancar la app se barren los restos que hubieran quedado de una sesión anterior. En Linux y Windows el selector devuelve tu fichero original: lo leemos para cifrar la copia que se envía, y no lo modificamos ni lo borramos. El contenido de cada fichero guardado está sellado, pero el listado del directorio no: cuántos adjuntos tenés, de qué tamaño y de qué fecha son metadatos del sistema de ficheros.",
            "Contactos: alias local, token y clave pública del contacto. Es material público por diseño.",
            "Solicitudes de desconocidos: quien tiene tu token pero no está en tus contactos puede escribirte, y eso entra en una bandeja de solicitudes separada de tus chats —solo texto, hasta 5 mensajes de 4 KiB por remitente y 20 remitentes a la vez, sin adjuntos, sin llamadas y sin notificación—. Se guarda el token, la clave pública si la ruta la trae, las fechas y el contador. Aceptar la solicitud es lo que crea el contacto; descartarla borra sus mensajes.",
            "Metadatos locales: con quién hablás, marcas de tiempo, estado de entrega y la ruta del fichero de media viven dentro del fichero de base de datos, cifrado por completo con SQLCipher (AES-256) bajo una clave derivada de la del almacén seguro del SO. Un fichero sacado del disco —portátil robado, móvil apagado, backup recuperado, otra cuenta del sistema— no se puede leer sin esa clave. Con el dispositivo desbloqueado y el llavero accesible es otra cosa: quien obtiene la clave abre la base y ve tanto esos metadatos como el contenido. Esa frontera la pone el bloqueo del sistema operativo.",
          ],
          "No existe cuenta, número de teléfono, correo ni contraseña asociados a vos en ningún servidor nuestro.",
        ],
      },
      {
        id: "no-recopilamos",
        title: "Qué no recopilamos",
        blocks: [
          [
            "Sin registro ni cuenta: no pedimos teléfono, correo ni nombre.",
            "Sin agenda: no subimos tus contactos ni operamos un directorio telefónico central.",
            "Sin analítica ni telemetría en la app: no hay SDK de métricas, ni crash reporting, ni identificadores de publicidad.",
            "Sin publicidad y sin venta ni cesión de datos a terceros.",
            "Sin copia de seguridad en la nube: en Android el backup automático del sistema está desactivado para la app.",
          ],
        ],
      },
      {
        id: "relay",
        title: "Relay ciego (opcional)",
        blocks: [
          "Si tu contacto está offline, podés configurar un relay para que guarde el mensaje cifrado hasta que se reconecte. Está desactivado salvo que lo configures, y el relay puede estar operado por un tercero, en cuyo caso aplican además sus condiciones.",
          "Lo que ese relay puede ver:",
          [
            "El token de destino al que va dirigido el sobre.",
            "El tamaño en bytes del sobre cifrado.",
            "La hora de depósito, la de entrega y el tiempo de vida (TTL).",
            "La dirección IP desde la que tu dispositivo deposita o consulta.",
          ],
          "Lo que no puede ver: el texto, las fotos, tu clave privada ni la clave de sesión. El sobre se borra tras la entrega o al expirar el TTL.",
          "Sobre la autoría, que en versiones anteriores de esta página figuraba como limitación abierta: el remitente sí está autenticado criptográficamente, y en las dos rutas. En el sobre que pasa por un relay, el remitente queda ligado al contenido, así que el token al que se atribuye un mensaje sale del propio criptograma; el campo de remitente que antes viajaba declarado ya no existe en el formato. En la conexión directa, abrir sesión exige probar posesión de la clave privada. Tener tu clave pública —viaja en la tarjeta de contacto que compartís— ya no alcanza para presentarse como vos.",
          "Por eso bloquear a alguien sirve: la decisión se toma contra esa identidad autenticada y no contra un dato que el emisor elija, y cubre también las codificaciones alternativas de una misma clave, que antes daban un token distinto y servían para volver. Lo que el bloqueo no puede impedir es que la misma persona genere una identidad nueva, ni —siendo local y unilateral— que siga depositando en un buzón que tu dispositivo ya no vacía. Y lo que sigue en pie de este apartado son los metadatos de arriba: no podés comprobar desde fuera que un relay respete el TTL o que no registre esa correlación, así que la conexión directa sigue siendo preferible.",
        ],
      },
      {
        id: "llamadas",
        title: "Llamadas de audio y vídeo",
        blocks: [
          "El audio y el vídeo van directos entre los dos dispositivos por WebRTC con cifrado DTLS-SRTP. No hay SFU, mezclador ni servidor de media de Encrypchat: los paquetes no pasan por nosotros. La señalización (invitación, SDP e ICE) viaja cifrada por el canal P2P ya establecido y nunca por el relay.",
          "Para descubrir la dirección pública de cada extremo se usan servidores STUN públicos de Google (stun.l.google.com y stun1.l.google.com). Google puede ver tu dirección IP y el momento en que intentás una llamada, no el contenido.",
          "Además, en cualquier conexión P2P tu contacto ve tu IP y vos la suya: es inherente a hablar directo, sin intermediario. Hoy no hay servidor TURN, así que en redes con NAT estricto la llamada puede no establecerse.",
          "Sobre quién llama: la identidad del par se verifica al establecer la conexión, así que una llamada entrante viene de quien es dueño de ese token. Una invitación de un token que no está en tus contactos se descarta sin sonar, y el micrófono y la cámara solo se activan si aceptás. Si bloqueás a alguien con la llamada en curso, se corta.",
          "El residual honesto aquí no es de autoría, es de exposición: al establecer la conexión, quien llama se identifica primero ante quien contesta. Quien contesta no revela nada hasta haber verificado a la otra parte, pero alguien que genere una identidad desechable y complete el intercambio puede confirmar que ese token está detrás de esa dirección IP. Cerrarlo del todo exige marcar con la clave pública del destino y no con su token, que es un hash.",
        ],
      },
      {
        id: "permisos",
        title: "Permisos del dispositivo",
        blocks: [
          "La app pide cada permiso en el momento en que hace falta y solo para la función indicada:",
          [
            "Micrófono (Android RECORD_AUDIO, iOS NSMicrophoneUsageDescription): capturar tu voz al iniciar o aceptar una llamada.",
            "Cámara (Android CAMERA, iOS NSCameraUsageDescription): capturar tu vídeo en una videollamada.",
            "Ajustes de audio y Bluetooth (Android MODIFY_AUDIO_SETTINGS, BLUETOOTH_CONNECT): rutear el audio de la llamada al altavoz o a unos auriculares.",
            "Fototeca en iOS (NSPhotoLibraryUsageDescription): el sistema puede pedirte acceso cuando elegís una foto para adjuntar. La app recibe solo la imagen que seleccionaste.",
            "Internet: conectar con tu contacto y, si lo configuraste, con el relay.",
          ],
          "En Android no pedimos permiso de galería: la app ya no declara READ_MEDIA_IMAGES ni READ_EXTERNAL_STORAGE. Al adjuntar se abre el selector de fotos del sistema, que nos entrega únicamente la foto que elegiste; el resto de tu galería sigue fuera de nuestro alcance. En dispositivos antiguos que no traen ese selector se abre el explorador de ficheros del sistema: cambia la experiencia, no el permiso, porque tampoco pide ninguno y también devuelve solo el fichero elegido. En Linux y Windows el diálogo de ficheros del sistema funciona igual.",
          "Ninguno de estos permisos se usa para recopilar datos en segundo plano ni para perfilar. El micrófono y la cámara solo se activan durante una llamada en curso.",
        ],
      },
      {
        id: "sitio-web",
        title: "Este sitio (encrypchat.com)",
        blocks: [
          "encrypchat.com es un sitio estático de marketing y descargas. No es el chat, no hay inicio de sesión y no se procesa contenido de usuarios.",
          [
            "Sin cookies propias, sin analítica y sin píxeles de terceros.",
            "Las tipografías se sirven desde nuestro propio dominio: visitar el sitio no genera una petición a Google Fonts.",
            "El proveedor de hosting (Cloudflare Pages) registra logs de acceso estándar (IP, user agent, hora) para servir el sitio y mitigar abuso, sujetos a su propia política.",
          ],
          "Si algún día añadimos analítica, se anunciará en esta página antes de activarla.",
        ],
      },
      {
        id: "terceros",
        title: "Terceros implicados",
        blocks: [
          [
            "Cloudflare: hosting del sitio web.",
            "Google STUN: conectividad de llamadas (ve IP y momento de la llamada).",
            "El operador del relay que elijas, si activás la entrega offline.",
            "Google Play y App Store cuando la app se publique: gestionan la descarga y sus propios datos de cuenta, fuera de nuestro alcance.",
          ],
          "Encrypchat no envía tus datos a ningún otro tercero.",
        ],
      },
      {
        id: "retencion",
        title: "Retención y borrado",
        blocks: [
          [
            "En tu dispositivo: los mensajes y la media se conservan hasta que los borres o desinstales la app. Borrar algo en tu dispositivo no lo borra del dispositivo de tu contacto.",
            "En el relay: el sobre cifrado se borra tras la entrega o al expirar su TTL, lo que ocurra primero.",
            "Al desinstalar: desaparecen la base de datos local, los ficheros de media y el resto del directorio privado de la app. No hay copia en la nube ni recuperación de cuenta, así que tus conversaciones se pierden de forma irreversible. Si querés conservar tus contactos, exportalos desde la app antes de desinstalar.",
            "La clave privada, en cambio, solo se va con la app en Android, donde se guarda dentro del directorio de datos de la app. En iOS, Linux y Windows queda en el llavero del sistema (Keychain, libsecret y el Administrador de credenciales), que por diseño sobrevive a desinstalar una aplicación. Esa clave sola no abre ninguna conversación —los mensajes y la media ya no están en el dispositivo—: es un residuo de identidad, no un archivo de tus chats. Para eliminarla del todo, borrá a mano la entrada de Encrypchat en el llavero del sistema.",
            "Todavía no hay dentro de la app una acción de «borrar identidad». Está evaluada y aplazada a propósito: borrar el material es sencillo, pero dejar la app en pie después obliga a rehacer el ciclo de vida de la sesión, y preferimos no ofrecer un botón que pueda dejarla en un estado inconsistente. Mientras tanto, la vía es desinstalar y, en iOS, Linux y Windows, limpiar esa entrada del llavero.",
          ],
        ],
      },
      {
        id: "derechos",
        title: "Tus derechos",
        blocks: [
          "Como no operamos un servidor de contenido, no tenemos una copia de tus mensajes que podamos entregarte, rectificar o borrar: esos derechos se ejercen directamente en tu dispositivo, donde tenés control total sobre los datos.",
          "Las solicitudes de acceso, rectificación, supresión, oposición o portabilidad (RGPD y equivalentes) se atenderán en el canal de contacto cuando esté activo. En la práctica, la respuesta será casi siempre que el dato no está en nuestro poder.",
          "Ejercer el borrado hoy significa desinstalar la app, lo que elimina chats y media, y en iOS, Linux y Windows borrar además la entrada de Encrypchat del llavero del sistema, que es donde queda la clave privada. La app todavía no trae una acción propia para hacerlo — está detallado en «Retención y borrado».",
        ],
      },
      {
        id: "menores",
        title: "Menores",
        blocks: [
          "Encrypchat no está dirigido a menores de 13 años y no recopila datos de ellos de forma consciente. La clasificación por edad definitiva de cada tienda está pendiente de completarse junto con el resto del expediente de publicación.",
        ],
      },
      {
        id: "limitaciones",
        title: "Lo que esta política no promete",
        blocks: [
          "Preferimos decirlo antes de que lo descubras:",
          [
            "No decimos «cero metadatos»: el relay ve destino, tamaño y tiempos, y STUN ve tu IP.",
            "No decimos «imposible de interceptar» ni «100 % privado». El cifrado reduce riesgo, no lo elimina.",
            "El cifrado de extremo a extremo no protege un dispositivo comprometido, una captura de pantalla, ni los backups del sistema operativo que hagas por tu cuenta.",
            "El cifrado del fichero de base de datos no protege un dispositivo desbloqueado: quien pueda leer la clave del llavero abre la base. Esa frontera la pone el bloqueo del sistema operativo.",
            "El listado del directorio de media queda visible aunque el contenido de cada fichero esté sellado: cuántos adjuntos hay, de qué tamaño y de qué fecha.",
            "El remitente sí está autenticado en las dos rutas y una clave pública ya no alcanza para suplantarte, pero no prometemos anonimato: el relay ve metadatos de red, quien llama se identifica primero ante quien contesta, y lo que hay en disco depende de que el dispositivo no esté comprometido.",
            "Cualquiera que tenga tu token puede dejarte una solicitud de texto sin ser contacto tuyo: va a una bandeja acotada, sin adjuntos ni llamadas y sin avisarte, pero no hay forma de impedir que ocupe uno de esos huecos ni de saber si tu token le llegó de quien creés.",
            "Desinstalar no borra la clave privada en iOS, Linux y Windows: queda en el llavero del sistema hasta que borres esa entrada a mano.",
            "El portapapeles no es nuestro: exportar un contacto, copiar tu token o guardar un informe de abuso pasan por el portapapeles del sistema, que en Windows conserva historial y en Android pueden leer otras apps.",
            "El sistema operativo guarda una miniatura de la última pantalla de cada app para el conmutador de tareas: si tenías una foto abierta, puede quedar ahí hasta que se refresque.",
            "El software es pre-1.0 y no ha pasado una auditoría de seguridad externa independiente.",
          ],
        ],
      },
      {
        id: "seguridad",
        title: "Reportar un fallo de seguridad",
        blocks: [
          "Si encontrás una vulnerabilidad en Encrypchat, escribinos a info@elnerd.com.",
          "Publicamos esa dirección en encrypchat.com, y solo aquí: en esta página y en https://encrypchat.com/.well-known/security.txt. Si la encontraste en otra parte, comprobala en una de las dos antes de escribir.",
          "Pedimos divulgación coordinada: contanos qué encontraste y dejanos un plazo razonable para corregirlo antes de publicarlo. No comprometemos tiempos de respuesta y no hay programa de recompensas. Sí publicamos los hallazgos y en qué estado están, incluidos los que siguen abiertos.",
          "Es el canal para fallos de seguridad del software. No es soporte, no es el buzón de privacidad y no sirve para denunciar a otro usuario: el informe de abuso de la app es local y no lo recibe nadie.",
        ],
      },
      {
        id: "cambios",
        title: "Cambios en esta política",
        blocks: [
          "La fecha de la última actualización figura al principio. Los cambios materiales se publicarán en esta página y, cuando existan versiones públicas, en sus notas de lanzamiento.",
        ],
      },
      {
        id: "contacto",
        title: "Contacto y jurisdicción",
        blocks: [
          "Pendiente de completar por el operador: entidad legal responsable, domicilio, correo de contacto de privacidad y ley aplicable.",
          "No hay hoy un buzón de privacidad operativo. La dirección que aparecía en el borrador anterior de esta página se ha retirado porque nunca llegó a activarse, y no publicamos direcciones que no funcionan.",
          "Para reportar un fallo de seguridad sí hay una dirección publicada: está en «Reportar un fallo de seguridad», más arriba.",
        ],
      },
    ],
  },
  terms: {
    metaTitle: "Términos de uso",
    metaDescription:
      "Términos de uso de Encrypchat: software cliente P2P en desarrollo, entregado tal cual, sin cuentas ni recuperación de claves y sin servicio de mensajería alojado.",
    h1: "Términos de uso",
    updated: "Última actualización: 12 de agosto de 2026 · versión 1.0 (previa a revisión legal)",
    updatedIso: "2026-08-12",
    summary:
      "Encrypchat es software cliente en desarrollo, entregado tal cual. No operamos un servicio de mensajería en la nube: no podemos leer, moderar, recuperar ni restaurar tus conversaciones.",
    disclaimer:
      "Este documento no es asesoría legal, todavía no lo ha revisado un abogado y hay campos pendientes de completar por el operador. Debe cerrarse antes de publicar en Google Play o la App Store.",
    sections: [
      {
        id: "aceptacion",
        title: "Aceptación",
        blocks: [
          "Al descargar, instalar o usar Encrypchat aceptás estos términos. Si no estás de acuerdo, no uses el software.",
        ],
      },
      {
        id: "servicio",
        title: "Qué es y qué no es el servicio",
        blocks: [
          "Encrypchat es software cliente para mensajería cifrada de igual a igual. Cada instalación funciona como cliente y como nodo local: son tus dispositivos los que se conectan entre sí.",
          "No vendemos ni operamos un servicio de mensajería alojado. La única infraestructura opcional es un relay ciego para entrega offline, que podés configurar o no, y los servidores STUN públicos que ayudan a establecer una llamada.",
        ],
      },
      {
        id: "estado",
        title: "Estado del software",
        blocks: [
          "Encrypchat es pre-1.0 y está en desarrollo activo. En consecuencia:",
          [
            "Las funciones pueden cambiar, romperse o desaparecer entre versiones.",
            "No hay garantía de entrega de mensajes ni de disponibilidad; puede haber pérdida de datos.",
            "Los binarios disponibles hoy son builds de prueba para instalación manual, no versiones publicadas en tiendas.",
            "El software no ha pasado una auditoría de seguridad externa independiente.",
          ],
        ],
      },
      {
        id: "claves",
        title: "Tus claves son tu responsabilidad",
        blocks: [
          "Tu identidad es un par de claves que solo existe en tu dispositivo. No hay recuperación de cuenta, restablecimiento de contraseña ni copia de respaldo del lado del servidor.",
          "Perder el dispositivo, borrar los datos de la app o desinstalarla elimina de forma irreversible tu historial de conversaciones, y no hay manera de recuperarlo. La clave privada solo se va junto con la app en Android: en iOS, Linux y Windows queda en el llavero del sistema hasta que borres esa entrada a mano. Protegé el dispositivo con el bloqueo del sistema operativo y decidí conscientemente qué backups hacés.",
        ],
      },
      {
        id: "uso",
        title: "Uso aceptable",
        blocks: [
          [
            "No uses Encrypchat para actividades ilegales en tu jurisdicción, acoso, distribución de malware o spam.",
            "No abuses de la infraestructura opcional que operemos: puede aplicar límites de tasa y cuotas, y no está permitido eludirlos.",
            "No intentes suplantar a otro usuario ni interferir con la disponibilidad del servicio para terceros.",
          ],
          "Podemos rechazar el uso abusivo de cualquier infraestructura que operemos. No podemos, en cambio, bloquear una conversación directa entre dos dispositivos: la arquitectura no nos lo permite.",
        ],
      },
      {
        id: "contenido",
        title: "Contenido y moderación",
        blocks: [
          "El contenido lo generan y lo transmiten las personas usuarias. No lo alojamos en claro, no podemos leerlo y por tanto no podemos moderarlo, filtrarlo ni entregarlo a un tercero. La responsabilidad legal de lo que envías es tuya.",
          "Tené en cuenta que en una conexión punto a punto tu dirección IP es visible para tu contacto, igual que la suya lo es para vos.",
        ],
      },
      {
        id: "terceros",
        title: "Servicios de terceros",
        blocks: [
          "El relay que configures (propio o ajeno) y los servidores STUN públicos se rigen por sus propias condiciones y políticas. No respondemos por su disponibilidad, su retención de logs ni sus cambios de servicio.",
        ],
      },
      {
        id: "propiedad",
        title: "Propiedad intelectual y licencia",
        blocks: [
          "La marca Encrypchat y su logotipo pertenecen al proyecto. El código fuente está hoy bajo «todos los derechos reservados», con la licencia definitiva pendiente de decisión: no se concede permiso de redistribución ni de obra derivada hasta que se publique.",
          "La aplicación se distribuye sin coste y no incluye compras dentro de la app ni suscripciones.",
        ],
      },
      {
        id: "exportacion",
        title: "Criptografía y control de exportación",
        blocks: [
          "Encrypchat incluye criptografía estándar y ampliamente disponible: X25519 y ChaCha20-Poly1305 para mensajes y ficheros, DTLS-SRTP para llamadas, y AES-256 con HMAC-SHA256 para el cifrado de la base de datos local (SQLCipher, que enlaza OpenSSL). Sos responsable de cumplir la normativa de importación, uso y exportación de criptografía aplicable en tu jurisdicción.",
          "La declaración formal de exportación que exigen las tiendas de aplicaciones está pendiente de completarse antes de la publicación.",
        ],
      },
      {
        id: "garantias",
        title: "Sin garantías",
        blocks: [
          "El software se entrega «tal cual» y «según disponibilidad», sin garantías expresas ni implícitas de comerciabilidad, adecuación a un fin concreto o ausencia de defectos.",
          "El cifrado reduce el riesgo, no lo elimina. La seguridad del dispositivo, el acceso físico, el malware y el análisis de metadatos de red siguen siendo amenazas reales.",
        ],
      },
      {
        id: "responsabilidad",
        title: "Limitación de responsabilidad",
        blocks: [
          "Hasta el máximo permitido por la ley aplicable, no respondemos por daños indirectos, incidentales o consecuentes, ni por pérdida de datos, de mensajes o de identidad derivada del uso del software.",
          "El límite cuantitativo de responsabilidad queda pendiente de fijar junto con la entidad legal.",
        ],
      },
      {
        id: "cambios",
        title: "Cambios y terminación",
        blocks: [
          "Podemos actualizar estos términos y retirar o modificar cualquier infraestructura opcional. El software ya instalado sigue funcionando de forma directa entre dispositivos aunque esa infraestructura desaparezca.",
        ],
      },
      {
        id: "ley",
        title: "Ley aplicable y contacto",
        blocks: [
          "Pendiente de completar por el operador: entidad legal, ley aplicable, foro competente y canal de contacto. Hasta entonces no hay una dirección de contacto general publicada. Para reportar un fallo de seguridad sí hay una, en la política de privacidad.",
        ],
      },
    ],
  },
  redirect: {
    message: "Redirigiendo a Encrypchat…",
    link: "Continuar en inglés",
  },
  demo: {
    peerName: "María Ruiz",
    diegoName: "Diego Soto",
    anaName: "Ana López",
    chatsLabel: "Chats",
    statusOnline: "P2P · en línea",
    dayToday: "Hoy",
    e2eeBanner: "Cifrado E2EE · en este dispositivo",
    draftText: "Estoy abajo",
    videoCallHint: "Cifrado en este dispositivo",
    videoCallBadge: "P2P · 02:14",
    videoCallYou: "Tú",
    yesterday: "Ayer",
    mondayShort: "Lun",
    m1: "¿Seguimos con el café de la esquina a las 10?",
    m2: "Dale. ¿Sigue abierta la terraza?",
    m3Caption: "Acabo de pasar — terraza libre",
    m3Alt: "Fachada del café",
    m4Caption: "Perfecto, agarro esa mesa",
    m4Alt: "Mesa con café",
    m5Caption: "Salgo ya — así se llega",
    m5Alt: "Calle hacia el café",
    m6: "Te veo mejor por video un segundo — se me cruzó el mapa",
    callLabel: "Videollamada P2P",
    callDetail: "2:14 · cifrado en dispositivo",
    s1: "¿Llegas por la terraza?",
    s2: "En 5 — voy por la esquina",
    s3Caption: "Mesa libre",
    diegoPreview: "Nos vemos en Fedora",
    anaPreview: "Clave por QR listo",
  },
};

export default es;
