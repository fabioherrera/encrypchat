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
    security: "Seguridad",
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
    apk: "APK arm64",
    rpm: "RPM Fedora",
    tarball: "tar.gz portable",
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
    platformsNote:
      "Estamos en testing. Android y Linux tienen build de prueba. iOS y Windows todavía no tienen paquete aquí.",
    testingBadge: "En pruebas",
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
    metaTitle: "Descargar — en pruebas",
    metaDescription:
      "Encrypchat está en pruebas. APK Android y RPM o tar.gz para Linux, sin firmar. iOS y Windows todavía no.",
    h1: "Descargar",
    testingBadge: "En pruebas",
    testingLead:
      "Estamos en testing. Estos instaladores sirven para probar en dispositivos reales, no son una versión de tienda ni un lanzamiento público.",
    intro:
      "Android y Linux tienen paquete. iOS necesita un Mac; Windows se compila en una máquina Windows.",
    privateNote:
      "El código y estos instaladores están en GitHub. Siguen siendo de prueba: no hay ficha de tienda ni lanzamiento público.",
    unsignedNote:
      "Nada está firmado. Fedora lo dice al instalar. El APK va con la clave de depuración: sirve para sideload, no para Play Store, y cambiar esa clave más adelante obliga a desinstalar — lo que en Android sí borra la base local.",
    androidSideload:
      "En Android el sistema bloquea el APK porque no está en Play Store. Eso es lo esperado. Bajalo, abrilo desde Archivos o Descargas, y cuando avise «por tu seguridad» o Play Protect: Ajustes → Aplicaciones → Acceso especial → Instalar apps desconocidas → Chrome o Archivos → Permitir. Después «Instalar de todos modos». Solo teléfonos arm64 (casi todos los de los últimos años).",
    checksums: "Comprobar SHA-256",
    releasePage: "Notas de esta tanda",
    sourceNote:
      "Windows: en la máquina, scripts\\package-windows.ps1. iOS: hace falta un host macOS (scripts/package-ios.sh). El código está en el mismo repositorio.",
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
        a: "Android, iOS, Linux (Fedora) y Windows son objetivos de primera clase. Hoy hay APK para Android y RPM o tar.gz para Linux, como builds de prueba en GitHub Releases. iOS y Windows todavía no tienen paquete en esa lista. Las tiendas, cuando empiece la publicación.",
      },
      {
        q: "¿Cómo agrego un contacto?",
        a: "El otro escanea el QR de Mi token con la cámara (en Linux y Windows se pega el export, o se lee una foto del QR). No hay un directorio telefónico central como fuente de verdad.",
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
        a: "Desde la app, con «borrar identidad»: quita primero la clave del llavero del sistema y después la base de datos y los adjuntos, así que no hay que limpiar nada a mano. Si se interrumpe, se reanuda en el siguiente arranque antes de abrir nada. Lo que ese borrado no puede hacer es sobreescribir los bytes: quedan como cifrado sin clave, no como hueco en blanco, y un backup del sistema anterior al borrado puede seguir teniendo la clave. Desinstalar sin más también se lleva la base de datos y los ficheros de media, pero en iOS, Linux y Windows deja la clave privada en el llavero del sistema hasta que borres esa entrada a mano.",
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
            "Informes de abuso que guardes: la app los escribe como fichero de texto donde le digas y, en móvil, en su propia carpeta. Ese fichero queda fuera de la base cifrada, lleva tu token y el del token reportado, y no lo recibe nadie: se queda en tu dispositivo hasta que lo borres. Si quedó en la carpeta de la app, el borrado de identidad se lo lleva; si lo guardaste en otra ruta, es tuyo.",
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
            "Cámara (Android CAMERA, iOS NSCameraUsageDescription): escanear el QR de un contacto y capturar tu vídeo en una videollamada. En los dos casos los fotogramas se procesan en el dispositivo y no se suben a ningún servidor de Encrypchat. En Linux y Windows no hay cámara en vivo para el QR: se lee desde una imagen o se pega el export.",
            "Ajustes de audio y Bluetooth (Android MODIFY_AUDIO_SETTINGS, BLUETOOTH_CONNECT): rutear el audio de la llamada al altavoz o a unos auriculares.",
            "Fototeca en iOS (NSPhotoLibraryUsageDescription): el sistema puede pedirte acceso cuando elegís una foto para adjuntar. La app recibe solo la imagen que seleccionaste.",
            "Internet: conectar con tu contacto y, si lo configuraste, con el relay.",
          ],
          "En Android no pedimos permiso de galería: la app ya no declara READ_MEDIA_IMAGES ni READ_EXTERNAL_STORAGE. Al adjuntar se abre el selector de fotos del sistema, que nos entrega únicamente la foto que elegiste; el resto de tu galería sigue fuera de nuestro alcance. En dispositivos antiguos que no traen ese selector se abre el explorador de ficheros del sistema: cambia la experiencia, no el permiso, porque tampoco pide ninguno y también devuelve solo el fichero elegido. En Linux y Windows el diálogo de ficheros del sistema funciona igual.",
          "Ninguno de estos permisos se usa para recopilar datos en segundo plano ni para perfilar. El micrófono solo se activa durante una llamada. La cámara se activa durante una videollamada y mientras está abierta la pantalla de escanear un contacto; al salir, se apaga.",
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
            "En tu dispositivo: los mensajes y la media se conservan hasta que los borres, hasta que uses «borrar identidad» o hasta que desinstales la app. Borrar algo en tu dispositivo no lo borra del dispositivo de tu contacto.",
            "En el relay: el sobre cifrado se borra tras la entrega o al expirar su TTL, lo que ocurra primero.",
            "Al desinstalar: desaparecen la base de datos local, los ficheros de media y el resto del directorio privado de la app. No hay copia en la nube ni recuperación de cuenta, así que tus conversaciones se pierden de forma irreversible. Si querés conservar tus contactos, exportalos desde la app antes de desinstalar.",
            "La clave privada, en cambio, solo se va con la app en Android, donde se guarda dentro del directorio de datos de la app. En iOS, Linux y Windows queda en el llavero del sistema (Keychain, libsecret y el Administrador de credenciales), que por diseño sobrevive a desinstalar una aplicación. Esa clave sola no abre ninguna conversación —los mensajes y la media ya no están en el dispositivo—: es un residuo de identidad, no un archivo de tus chats. Para eliminarla del todo sin tocar el llavero a mano, usá «borrar identidad» dentro de la app antes de desinstalar.",
            "Con «borrar identidad», dentro de la app: quita primero la clave del llavero del sistema y después la base de datos y los adjuntos. Si se interrumpe, se reanuda en el siguiente arranque antes de abrir nada. Si el sistema se niega a eliminar algún fichero —pasa en Windows cuando otro proceso lo tiene abierto—, la app te dice cuántos quedaron en vez de darlo por completo. Lo que no puede hacer es sobreescribir los bytes: quedan como cifrado sin clave, no como hueco en blanco, y un backup del sistema anterior al borrado puede seguir teniendo la clave.",
            "Ese borrado también se lleva los informes de abuso que la app archivó en su propia carpeta, que son texto en claro con tu token y el del reportado. Lo que no alcanza es lo que sacaste vos a otra ruta: un informe guardado con el diálogo del sistema o un contacto exportado están donde los pusiste, fuera de lo que la app puede ver, y se borran como cualquier otro fichero tuyo.",
          ],
        ],
      },
      {
        id: "derechos",
        title: "Tus derechos",
        blocks: [
          "Como no operamos un servidor de contenido, no tenemos una copia de tus mensajes que podamos entregarte, rectificar o borrar: esos derechos se ejercen directamente en tu dispositivo, donde tenés control total sobre los datos.",
          "Las solicitudes de acceso, rectificación, supresión, oposición o portabilidad (RGPD y equivalentes) se atenderán en el canal de contacto cuando esté activo. En la práctica, la respuesta será casi siempre que el dato no está en nuestro poder.",
          "Ejercer el borrado significa usar «borrar identidad» dentro de la app: quita la clave del llavero del sistema y después la base de datos y los adjuntos de este dispositivo. Desinstalar también se lleva chats y media, pero en iOS, Linux y Windows deja la clave privada en el llavero hasta que borres esa entrada a mano — está detallado en «Retención y borrado».",
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
            "Desinstalar no borra la clave privada en iOS, Linux y Windows: queda en el llavero del sistema hasta que borres esa entrada a mano, o hasta que uses «borrar identidad» dentro de la app, que sí la quita. Ninguno de los dos caminos sobreescribe los bytes que ya estaban en disco: quedan como cifrado sin clave.",
            "El portapapeles no es nuestro: exportar un contacto o copiar tu token pasan por el portapapeles del sistema, que en Windows conserva historial y en Android pueden leer otras apps. El informe de abuso ya no pasa por ahí —se guarda como fichero— y copiarlo es una segunda acción que elegís vos.",
            "El sistema operativo guarda una miniatura de la última pantalla de cada app para el conmutador de tareas: si tenías una foto abierta, puede quedar ahí hasta que se refresque.",
            "El software es pre-1.0 y no ha pasado una auditoría de seguridad externa independiente.",
          ],
        ],
        links: [
          { path: "/security", hash: "limitaciones", label: "Modelo de amenazas: limitaciones" },
        ],
      },
      {
        id: "seguridad",
        title: "Reportar un fallo de seguridad",
        blocks: [
          "Si encontrás una vulnerabilidad en Encrypchat, escribinos a info@elnerd.com.",
          "Publicamos esa dirección en encrypchat.com, y solo aquí: en esta página, en la página de seguridad y en https://encrypchat.com/.well-known/security.txt. Si la encontraste en otra parte, comprobala en una de las tres antes de escribir.",
          "Pedimos divulgación coordinada: contanos qué encontraste y dejanos un plazo razonable para corregirlo antes de publicarlo. No comprometemos tiempos de respuesta y no hay programa de recompensas. Sí publicamos los hallazgos y en qué estado están, incluidos los que siguen abiertos.",
          "Es el canal para fallos de seguridad del software. No es soporte, no es el buzón de privacidad y no sirve para denunciar a otro usuario: el informe de abuso de la app es local y no lo recibe nadie.",
          "Antes de escribir, vale la pena leer el modelo de amenazas: dice de qué protege el producto, de qué no y qué limitaciones ya conocemos y hemos publicado.",
        ],
        links: [
          { path: "/security", hash: "reportar", label: "Modelo de amenazas: cómo reportar" },
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
          "Perder el dispositivo, borrar los datos de la app, usar «borrar identidad» o desinstalarla elimina de forma irreversible tu historial de conversaciones, y no hay manera de recuperarlo. «Borrar identidad» quita además la clave privada del llavero del sistema; si solo desinstalás, en iOS, Linux y Windows la clave queda ahí hasta que borres esa entrada a mano. Protegé el dispositivo con el bloqueo del sistema operativo y decidí conscientemente qué backups hacés.",
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
  security: {
    metaTitle: "Seguridad y modelo de amenazas",
    metaDescription:
      "De qué protege Encrypchat y de qué no: adversarios, metadatos, la lista de limitaciones abiertas y cómo reportar una vulnerabilidad.",
    h1: "Seguridad y modelo de amenazas",
    updated: "Última revisión: 12 de agosto de 2026 · estado del producto: pre-beta (fase 10)",
    updatedIso: "2026-08-12",
    summary:
      "Encrypchat cifra el contenido en el dispositivo de origen y no tiene ningún servidor que lo guarde. Esta página dice de qué protege eso, de qué no, y quién aprende qué. Un producto de privacidad que no publica sus límites está mintiendo por omisión, así que la parte importante es la lista de limitaciones conocidas, y está entera más abajo.",
    disclaimer:
      "Es la versión web del modelo de amenazas que se mantiene junto al código (docs/threat-model.md): describe el estado real del software en la fecha de arriba, no el que nos gustaría. El software es pre-1.0 y no ha pasado una auditoría de seguridad externa independiente. Está escrito para que lo entienda alguien que no es criptógrafo y para que un criptógrafo pueda verificarlo contra el código; si hay una diferencia entre lo que dice esta página y lo que hace el código, la página está mal y queremos saberlo.",
    sections: [
      {
        id: "resumen",
        title: "Qué es Encrypchat, en una página",
        blocks: [
          [
            "Cada dispositivo es a la vez cliente y nodo. No hay servidor que guarde chats, media ni claves.",
            "La identidad es un par de claves X25519 generado en el dispositivo. El token («ec_» más 64 caracteres hexadecimales) es el hash SHA-256 de la clave pública. No hay registro, ni teléfono, ni correo, ni cuenta.",
            "Los mensajes se cifran en origen con la clave pública del destinatario (X25519 efímero más ChaCha20-Poly1305) y viajan por TCP directo entre los dos dispositivos.",
            "Si el otro está desconectado, el mensaje ya cifrado puede quedar en un relay ciego: un buzón que guarda un blob opaco con tiempo de vida y lo borra cuando lo ha entregado, tras una segunda entrega de cortesía o al vencer ese plazo.",
            "Las llamadas son WebRTC directo con DTLS-SRTP.",
          ],
        ],
        links: [
          { path: "/features", label: "Cómo funciona" },
          { path: "/download", label: "Descargar la app" },
        ],
      },
      {
        id: "protegemos",
        title: "Qué protegemos",
        blocks: [
          [
            "Clave privada de identidad: vive en el almacén seguro del sistema operativo (Keystore, Keychain, libsecret, DPAPI). Nunca sale del dispositivo, no viaja por la red y no aparece en los logs.",
            "Contenido de los mensajes: cifrado en el dispositivo de origen. Ni el relay ni la red ven el texto.",
            "Ficheros y fotos: cifrados en origen para el envío y sellados con cifrado autenticado en disco.",
            "Audio y vídeo: DTLS-SRTP entre los dos dispositivos, sin servidor de medios nuestro ni de terceros.",
            "Cuerpos de mensaje en reposo: el fichero de base de datos va cifrado con SQLCipher (AES-256) y, encima, cada cuerpo sellado con cifrado autenticado. Las dos claves salen del almacén seguro del sistema.",
            "Autoría de un mensaje: el remitente queda atado al contenido, con prueba de posesión en el handshake P2P (EH02) y sobre con remitente sellado en la ruta de relay (ECS1).",
          ],
        ],
      },
      {
        id: "red-local",
        title: "Alguien en tu misma red",
        blocks: [
          "No puede leer el contenido de mensajes, ficheros ni llamadas: todo va cifrado antes de salir del dispositivo.",
          "Sí puede ver que dos direcciones IP intercambian tráfico, cuánto y cuándo; deducir cosas del tamaño por encima de 512 bytes, que es donde el relleno deja de igualarlo todo (una foto no se confunde con un mensaje corto, pero un mensaje corto tampoco se distingue de un acuse de recibo); cortarte la conexión; y, si el relay está configurado sin TLS, leer tu token y el del destinatario en claro — la app avisa de forma persistente cuando eso pasa.",
          "Ya no puede hacerse pasar por vos teniendo tu clave pública: el handshake exige probar posesión de la privada, y el sobre que viaja por el relay ata al remitente con su contenido. Tampoco aprende identidades escuchando, ni del handshake ni de las tramas de una sesión ya abierta.",
          "Sí puede, y es el residual de este apartado: abrir una conexión a tu puerto con una identidad desechable y, completando el handshake, confirmar qué token está detrás de esa dirección IP.",
        ],
      },
      {
        id: "relay-operador",
        title: "El operador del relay",
        blocks: [
          "El relay es opcional y solo interviene cuando el destinatario está desconectado. Guarda el token del destinatario, un blob cifrado y una fecha de caducidad.",
          "No puede leer el contenido: no tiene ninguna clave que lo permita y el diseño no contempla dársela. Tampoco puede recuperar tu identidad desde el token, que es un hash.",
          "Sí puede saber que alguien depositó un mensaje para «ec_abc…», de qué tamaño y a qué hora; ver la dirección IP de quien deposita y la de quien recoge, y por tanto correlacionar «esta IP escribe a este token» con «esta IP es dueña de este token»; retener blobs más de lo que promete o registrar esa correlación, sin que puedas verificarlo desde fuera; y negarse a entregar.",
          "No confíes en el relay para el anonimato. El relay ciego protege el contenido, no la relación. Si tu adversario incluye a quien opera la infraestructura, usá solo conexión directa, o poné Tor o una VPN por debajo.",
        ],
        links: [{ path: "/privacy", hash: "relay", label: "Privacidad: relay ciego" }],
      },
      {
        id: "acceso-fisico",
        title: "Alguien con acceso físico al dispositivo",
        blocks: [
          "Bloqueado, con contraseña o biometría: la defensa principal es el cifrado del sistema operativo, no la nuestra.",
          "Desbloqueado: Encrypchat no te protege. Quien tenga la sesión abierta lee todo lo que vos leés. No hay PIN de aplicación, ni bloqueo por inactividad, ni chats ocultos.",
          "Apagado, o con el disco sin cifrar: el fichero de base de datos está cifrado con SQLCipher bajo una clave derivada de la del almacén seguro, así que un portátil robado, un móvil apagado o un backup recuperado no revelan con quién hablás, tus contactos, las fechas ni las rutas de tus adjuntos. Lo que sí queda visible es el listado del directorio de media: el contenido de cada fichero está sellado, pero cuántos hay, su tamaño y su fecha son metadatos del sistema de ficheros. Cifrar el disco del dispositivo sigue siendo buena idea.",
          "Sobre desinstalar: en iOS, Linux y Windows la clave privada sobrevive a desinstalar la app, porque vive en el almacén del sistema y esas plataformas no lo limpian. Solo en Android desaparece con la app. Para irte del todo está el borrado de identidad dentro de la app, que quita la clave del llavero y después la base de datos y los adjuntos; si se interrumpe, se reanuda en el siguiente arranque antes de abrir nada. Lo que ese borrado no puede hacer es sobreescribir los bytes: quedan como cifrado sin clave, no como hueco en blanco, y un backup del sistema anterior al borrado puede seguir teniendo la clave.",
        ],
      },
      {
        id: "sistema-operativo",
        title: "El proveedor de tu sistema operativo",
        blocks: [
          "Apple, Google, Microsoft y tu distribución de Linux están por debajo de Encrypchat: controlan el teclado que escribe, la pantalla que muestra, el almacén donde vive la clave y la tienda desde la que descargaste la app.",
          "No podemos protegerte de ellos y no vamos a decir lo contrario. Lo que sí hacemos: no mandar nada a sus servicios que no haga falta, no usar notificaciones push —no hay, precisamente por eso— y no incluir analítica, SDK de terceros ni informes de fallos con contenido.",
          "Excepción explícita: las llamadas usan servidores STUN públicos de Google para descubrir tu dirección IP pública.",
        ],
      },
      {
        id: "estado",
        title: "Un atacante con recursos de estado",
        blocks: [
          "No puede, hasta donde sabemos hoy, romper X25519 ni ChaCha20-Poly1305, ni leer contenido capturado de la red.",
          "Sí puede ver tráfico a escala nacional y correlacionar quién habla con quién por tiempos y tamaños sin leer nada; comprometer un dispositivo con un exploit del sistema operativo, y ahí se acabó todo; intervenir o presionar a quien opere un relay; y bloquear el acceso.",
          "Encrypchat no es una herramienta de anonimato ni de resistencia a la censura. Protege el contenido y elimina el servidor central de contenido; no oculta que lo usás ni con quién.",
        ],
      },
      {
        id: "otro-lado",
        title: "La persona del otro lado",
        blocks: [
          "El adversario más frecuente en la vida real es alguien con quien ya hablaste.",
          "No puede leer tus conversaciones con terceros.",
          "Sí puede guardar, capturar y reenviar todo lo que le mandes: el cifrado no impide una captura de pantalla ni una foto con otro teléfono. Puede crear una identidad nueva en segundos si la bloqueás, porque los tokens no cuestan nada y no hay directorio central. Tiene tu clave pública, porque te tiene guardado, pero eso ya no le sirve para presentarse como vos ante nadie.",
          "Bloquear corta la entrega de mensajes, fotos y llamadas de ese token en dos capas: la app descarta el paquete antes de descifrarlo y el núcleo se niega a abrir o mantener sesión. Se aplica contra la identidad autenticada del remitente, no contra un campo que él elija, así que no se evade suplantando a otro contacto. Tampoco se evade reescribiendo la misma clave de otra forma: una clave pública tiene una sola codificación válida y las demás se rechazan al entrar. Si hay una llamada en curso con ese token, se corta antes de aplicar el bloqueo. No se le avisa, y no impide que vuelva con otra identidad.",
          "El bloqueo es local y unilateral: este dispositivo deja de aceptar, pero la otra parte puede seguir depositando en un buzón de relay que ya nadie vacía, hasta que caduque.",
          "Un desconocido —alguien que tiene tu token pero no está en tus contactos— no entra en tus chats: cae en una bandeja de solicitudes con techo, solo texto, sin sonido y sin poder dejarte ficheros en el disco. Aceptarlo es un acto explícito tuyo.",
        ],
      },
      {
        id: "fuera-de-alcance",
        title: "Fuera de alcance, por diseño",
        blocks: [
          "No son fallos pendientes: son cosas que Encrypchat no intenta hacer.",
          [
            "Anonimato de red. Tu dirección IP es visible para tu par y para el relay. Sin enrutado cebolla ni mixnet.",
            "Ocultar que usás Encrypchat. El protocolo no está ofuscado ni imita otro tráfico.",
            "Protegerte de tu propio dispositivo. Malware, teclados maliciosos o alguien mirando por encima del hombro quedan fuera.",
            "Impedir capturas de pantalla del otro lado. Ningún sistema de cifrado de extremo a extremo puede.",
            "Moderación de contenido. No hay servidor que pueda leer nada. El reporte de abuso genera un informe local que vos decidís qué hacer con él; nadie lo recibe automáticamente.",
            "Recuperación de cuenta. Si perdés la clave privada, perdiste la identidad. Tener reseteo significaría que alguien más puede tomarla.",
            "Sincronización entre dispositivos. Una identidad vive en un dispositivo; el historial no se sincroniza.",
            "Confidencialidad hacia adelante por mensaje. No hay ratchet, y el matiz importa según por dónde vaya el mensaje: ver el detalle en el apartado siguiente.",
            "Metadatos de red. No prometemos «cero metadatos» y no lo vamos a hacer mientras haya red de por medio.",
          ],
          "Sobre la confidencialidad hacia adelante, el matiz completo: en una sesión P2P sí la hay por sesión, porque la clave de transporte sale de un intercambio entre las dos claves efímeras del handshake, que se destruyen al terminarlo — quien haya grabado el tráfico y después consiga las dos claves de identidad no puede descifrar esa conversación. Lo que no hay es granularidad por mensaje: quien consiga la clave de una sesión, arrancándola de la memoria de un dispositivo mientras está viva, lee esa sesión entera. En la ruta de relay no hay confidencialidad hacia adelante en absoluto: el blob se cierra contra tu clave estática, así que quien obtenga tu clave privada y tenga blobs guardados los lee.",
        ],
      },
      {
        id: "metadatos",
        title: "Metadatos: quién aprende qué",
        blocks: [
          [
            "Un observador de la red (tu wifi, tu proveedor de internet) aprende que tu IP habla con otra IP, el volumen, los horarios, el tamaño de cada mensaje por encima de 512 bytes y que es tráfico de Encrypchat, por los primeros bytes del handshake. No aprende el contenido, ni identidades —ni en el handshake ni en las tramas de una sesión ya establecida, que van cifradas de punta a punta del socket—, ni la diferencia entre un acuse y un mensaje corto, ni los tokens de la ruta de relay si ese relay usa TLS.",
            "El operador del relay aprende el token del destinatario, el tamaño del blob, la hora de depósito y de recogida, y la dirección IP de ambas puntas. No aprende el contenido, el token del remitente ni los nombres de fichero.",
            "El STUN público de Google aprende tu dirección IP pública y el momento de iniciar o recibir una llamada. No aprende con quién hablás, qué decís ni tu token.",
            "Tu par aprende tu token, tu clave pública, tu dirección IP durante la conexión y todo lo que le enviás. No aprende tus otras conversaciones.",
            "Quien tenga tu dispositivo desbloqueado aprende todo.",
            "Encrypchat, es decir nosotros, no aprende nada de la app: no operamos servidores de contenido y no hay telemetría ni analítica. La única excepción no está en la app sino en este sitio web, que sirve Cloudflare y que registra logs de acceso estándar —dirección IP, agente de usuario y hora— como cualquier alojamiento.",
          ],
          "Tres notas honestas sobre esa lista. El relay ve el token del destinatario: es inevitable, porque sin él no sabe a qué buzón dejar el blob, y por eso es opcional y por eso preferimos siempre la conexión directa. El STUN de Google ve tu IP al llamar: es un tercero que no controlamos, y está ahí porque sin él las llamadas no atraviesan la mayoría de los NAT domésticos — si eso no te sirve, no uses llamadas. Y la correlación es el ataque realista: nadie va a romper ChaCha20, van a mirar quién habló con quién y cuándo.",
        ],
        links: [{ path: "/privacy", hash: "terceros", label: "Privacidad: terceros implicados" }],
      },
      {
        id: "identidad",
        title: "Identidad y token",
        blocks: [
          "Par de claves X25519 del generador aleatorio del sistema. El token es «ec_» más el hash SHA-256 de la clave pública en hexadecimal. La privada vive en el almacén seguro del sistema operativo. La tarjeta de contacto que compartís incluye tu clave pública en claro: es pública por diseño, porque quien te escribe la necesita.",
          "El token no autentica por sí mismo: es un identificador, no una credencial. Un token que llega por un canal que alguien controla puede ser el de esa persona. Verificalo por un canal aparte.",
          "Una clave, un token. Que el token sea un nombre estable para un par de claves exige que cada clave tenga una sola codificación, y X25519 no lo regala: la curva ignora el bit alto y reduce módulo p, así que varias cadenas de 32 bytes son la misma clave para un intercambio Diffie-Hellman y claves distintas para un hash. Toda clave pública que entra —tarjeta de contacto, QR, red, frontera con el núcleo— se rechaza si no viene en su forma reducida. Sin ese control, un bloqueado volvía con la misma clave escrita de otra manera y un token limpio.",
          "Falta: números de seguridad comparables dentro de la app y aviso cuando cambia la clave de un contacto.",
        ],
      },
      {
        id: "canal-p2p",
        title: "Canal P2P y handshake EH02",
        blocks: [
          "TCP directo con tramas de longitud prefijada. Al conectar corre EH02, cuatro mensajes con autenticación mutua: quien llama envía magia, versión y un nonce, sin identidad; quien escucha responde con una clave efímera de un solo uso y otro nonce, también sin identidad; quien llama prueba su identidad sellándola contra esa efímera; y quien escucha, sabiendo ya con quién habla, prueba la suya sellándola contra la clave del otro.",
          "Las dos pruebas usan el mismo primitivo de doble Diffie-Hellman que los blobs de relay: abrirlas exige un intercambio que solo puede calcular el verificador, y eso no se hace con la clave pública de la víctima. Cada prueba va atada por datos autenticados a la versión, al rol, a los dos nonces y a la efímera de la sesión, así que no sirve en otra conexión ni en el sentido contrario. Límites: 5 segundos de handshake, 32 conexiones sin autenticar a la vez y 4 KiB de buffer antes de autenticar.",
          "Esto sustituye a EH01, cuya prueba se podía construir con la clave pública del verificador y por tanto no probaba nada. Los dos extremos tienen que actualizarse a la vez, y un núcleo anterior no arranca en lugar de degradarse.",
          "Qué consigue en exposición de identidad: quien escucha no emite nada identificable hasta haber verificado a quien llama. Un observador pasivo de la red no aprende ninguna identidad del handshake, y quien abre una conexión sin poder probar ninguna identidad no obtiene nada. Un par bloqueado se rechaza entre el tercer y el cuarto mensaje, así que tampoco llega a saber quién le respondió.",
          "Qué no consigue: quien llama tiene que identificarse primero. No hay forma de probarle nada a alguien cuya clave todavía no conocés, así que un atacante que genere una identidad desechable y complete el handshake sí obtiene la identidad de quien escucha. Cerrarlo del todo exige que quien llama conozca la clave pública del otro de antemano; hoy el destino de una llamada se indica por token, y el token es un hash del que no se recupera la clave.",
          "Clave de sesión y transporte cifrado: cada extremo aporta una clave efímera de un solo uso, y de ellas sale la clave de sesión que cifra todo el transporte, cabecera incluida. Antes la cabecera viajaba en claro y solo el payload iba cifrado de extremo a extremo, así que quien esnifara la wifi leía el token del remitente de cada trama y podía dibujar el grafo social sin descifrar nada. Ahora un observador ve un prefijo de longitud y bytes opacos.",
          "Hay una clave por sentido, y el nonce es un contador implícito que nunca viaja: el receptor solo prueba el siguiente. Una trama repetida, reordenada, borrada o inyectada dentro de una sesión no descifra, y la sesión se cierra. Dentro de una sesión el flujo es exactamente una vez y en orden, o se corta.",
          "Lo que sigue viéndose es el tamaño. Todo lo que quepa en 512 bytes de texto plano sale con el mismo tamaño —un acuse, un «ok» y un párrafo corto son indistinguibles—, pero por encima de ahí la longitud es la del mensaje y una foto se distingue de un texto. Rellenar más no compensa: no esconde el volumen ni los tiempos, y el observador ya sabe qué IP habla con qué IP, que es el dato caro. Se declara como límite, no se disimula. También se ve que el tráfico es de Encrypchat: el primer mensaje del handshake empieza por «EH02».",
        ],
      },
      {
        id: "relay-ciego",
        title: "Relay ciego y prueba de posesión",
        blocks: [
          "Tres operaciones: depositar, pedir desafío y recoger. Recoger exige una prueba de posesión: el relay genera un par de claves efímero y un nonce, y solo entrega el buzón a quien demuestre con un intercambio Diffie-Hellman que es dueño del token. El desafío es de un solo uso, caduca en 2 minutos y no lleva destinatario, así que pedirlo no dice a qué buzón apunta nadie; se identifica por un id opaco, de modo que un tercero no puede pisar el desafío de otra persona y dejar su buzón sin vaciar. Se consume solo si la prueba verifica.",
          "Los blobs tienen tiempo de vida: 24 horas por defecto, 7 días como máximo. Al entregarse no se borran: quedan reservados 60 segundos, escondidos incluso de su destinatario, y se entregan una segunda y última vez si el cliente vuelve después. Así un cliente al que el sistema operativo mata entre la respuesta del relay y su propio guardado no pierde el mensaje. Hay cuota por buzón (8 MiB), techo global de disco y límite por dirección IP. Los logs no registran el token de destino.",
          "El sobre ata al remitente con su contenido: la clave que abre el cuerpo se deriva de la clave permanente del emisor contra la tuya, así que producir un blob que abra bien exige tener esa clave privada, y no hay un campo de remitente aparte que se pueda cambiar de sitio. Ese control tiene una propiedad deliberada: solo vos podés comprobarlo. La prueba no es transferible a un tercero —cualquiera con tu clave privada podría haber fabricado el mismo blob— y eso es a propósito, porque una firma pública convertiría cada mensaje en un recibo de quién te escribió. Sirve para atribuir y para bloquear; no sirve como prueba ante nadie más.",
          "Dos precisiones para que eso no se lea como más de lo que es. La negabilidad es criptográfica y va contra el blob: no va contra tu testimonio acompañado de indicios, y las horas, las direcciones IP y la correlación en el relay siguen existiendo. Y es negabilidad frente a terceros, no frente al destinatario: para él la atribución es fuerte, que es justo lo que hace que el bloqueo funcione.",
          "Lo que no da: el depósito no está autenticado, y el TLS es responsabilidad de quien opere el relay. La entrega es al menos una vez, dos como máximo: si el cliente muere en los dos intentos el mensaje se pierde igual, y el precio de los dos intentos es que cada blob cruza la red dos veces — la copia repetida la descarta el cliente por identificador de mensaje.",
        ],
      },
      {
        id: "llamadas",
        title: "Llamadas",
        blocks: [
          "La señalización viaja solo por el canal P2P, cifrada como cualquier mensaje, nunca por el relay. El medio va punto a punto con DTLS-SRTP. No hay SFU, ni TURN, ni servidor de medios: el audio y el vídeo nunca pasan por infraestructura nuestra. Sin TURN, algunas combinaciones de NAT no conectan; preferimos que la llamada falle antes que montar un servidor por el que pase tu voz.",
          "El micrófono y la cámara se piden al aceptar, no al sonar. Una invitación de un token que no está en tus contactos se descarta sin sonar.",
        ],
        links: [{ path: "/privacy", hash: "llamadas", label: "Privacidad: llamadas" }],
      },
      {
        id: "almacenamiento",
        title: "Almacenamiento local",
        blocks: [
          "SQLite en el directorio privado de la app, cifrado como fichero con SQLCipher bajo una clave derivada de la del almacén seguro — derivada, y no la misma, para no reutilizar los mismos bytes en dos primitivas. Encima de eso, los cuerpos de mensaje y los ficheros van sellados con ChaCha20-Poly1305: son dos capas distintas, y la de dentro sigue protegiendo si alguna vez se abre la base. En Android, el backup automático del sistema está desactivado para la app.",
          "Lo que el cifrado de fichero no cubre: un dispositivo desbloqueado con el llavero accesible —quien lee la clave abre la base, y ahí la frontera es la pantalla de bloqueo del sistema— y el listado del directorio de media, cuyo contenido está sellado pero cuyo número de ficheros, tamaños y fechas son metadatos del sistema de ficheros.",
          "Si el llavero pierde la clave, el historial se pierde: la app lo dice en pantalla en vez de empezar una base nueva encima.",
          "El disco no es infinito y el que lo llena es el otro lado, así que los adjuntos entrantes tienen techo: 512 MiB por par y 2 GiB en total, comprobado antes de escribir el fichero. Pasado el techo el adjunto se rechaza y la app te lo dice, en vez de crecer hasta que el sistema se queje. Un desconocido no llega ni a esa cuenta: la bandeja de solicitudes no acepta ficheros.",
        ],
      },
      {
        id: "frontera-ffi",
        title: "La frontera entre el núcleo y la interfaz",
        blocks: [
          "Criptografía, identidad y nodo P2P en Rust; interfaz en Flutter. Cada símbolo de la frontera tiene contrato escrito: qué punteros deben ser válidos, quién libera qué, qué se escribe en caso de error (nada) y cuánto bloquea cada llamada. Los puntos de entrada capturan pánicos y los convierten en código de error.",
          "Material sensible que cruza: la clave de identidad y la de la base de datos. Rust limpia sus copias y el puente en Dart limpia las suyas: todo buffer nativo que llevó una clave o un texto plano se pone a cero antes de liberarse, incluidos los que reserva el propio núcleo. Queda un residuo que el lenguaje no permite cerrar: la copia que vive en el heap de Dart —la clave de identidad mientras hay sesión, y la cadena en base64 que devuelve el almacén seguro al cargarla— la gestiona el recolector de basura, que puede haberla movido o duplicado. Cerrar eso significaría que la clave no cruce la frontera en cada mensaje, sino que el descifrado ocurra dentro del núcleo con la copia que el nodo ya tiene; es un cambio de la superficie de la frontera, no del cliente.",
          "Las llamadas de nodo con presupuesto de bloqueo —enviar, 15 segundos; marcar, 10— corren en un hilo aparte, así que un par que acepta la conexión y no contesta no congela la interfaz.",
        ],
      },
      {
        id: "limitaciones",
        title: "Limitaciones conocidas hoy",
        blocks: [
          "Estado real del código en la fecha de arriba. Se actualiza cuando cambia, no cuando conviene.",
          {
            ordered: [
              "La autoría la dan el transporte y el sobre, no el cifrado en sí. El handshake P2P prueba posesión de la clave privada y los blobs de relay atan al remitente: las dos suplantaciones que versiones anteriores de este documento describían como abiertas están cerradas, en el núcleo y en el cliente que las tiene que llamar. Lo que sigue siendo cierto es que la operación de cifrado por sí sola no dice quién escribió —cualquiera con tu clave pública puede producir algo que descifra bien—, así que cada ruta nueva que se añada tiene que autenticar explícitamente por uno de los dos caminos: la capa criptográfica no lo hace sola. Y la atribución que obtenés vale para vos, no ante un tercero.",
              "Un blob de relay reencolado ya no se muestra dos veces, pero sí puede llegar tarde. El cliente recuerda los identificadores de los sobres que abrió y descarta el repetido; la tabla se poda con la propia ventana de frescura, así que no crece sin límite. Lo que ese identificador no dice es cuándo correspondía: un sobre auténtico capturado y depositado más tarde, dentro de la ventana de 7 días, es nuevo para un dispositivo que nunca lo vio y se mostrará con su fecha original. Por eso la señalización de llamadas sigue sin salir por el relay: un timbre no molesta por repetido, molesta por llegar a las 4 de la madrugada.",
              "Bloquear no detiene a quien use una identidad nueva. El bloqueo se aplica siempre contra una identidad que el emisor no elige —probada por el handshake en P2P, sacada del criptograma en relay— y corta la llamada en curso antes de aplicarse. Lo que nadie puede impedir es que la misma persona genere otro token y vuelva.",
              "Un desconocido puede escribirte, con techo. Quien tenga tu token entra en la bandeja de solicitudes: solo texto, hasta 5 mensajes de 4 KiB por remitente y 20 remitentes a la vez, sin notificación y sin adjuntos ni llamadas. Todo lo que exceda eso se descarta antes de tocar el disco —y, si no sos contacto, antes incluso de descifrarlo—, así que el coste máximo de todos los desconocidos juntos son 400 KiB de texto y el ruido de tener que mirar la bandeja. Cuando los 20 huecos están ocupados, la solicitud más antigua se desaloja para dejar sitio a la nueva: es una ventana rodante, no una cola que se cierra. La consecuencia es que veinte identidades desechables —que no cuestan nada— pueden empujar fuera una solicitud que no llegaste a leer, aunque no pueden dejarte incomunicado de forma indefinida. Tampoco hay forma de saber si el token te llegó de quien creés.",
              "Alguien puede llenarte el buzón del relay, y en silencio. Depositar no exige autenticarse —hace falta para que cualquiera pueda escribirte estando vos desconectado—, así que quien conozca tu token puede ocupar tu cuota y hacer que los mensajes que te manden mientras tanto se pierdan. El relay responde a todos igual, aceptado o descartado, y esa opacidad es deliberada: distinguirlos convertía al relay en un delator de tu presencia, y avisar al remitente honesto es la misma petición que avisar a quien te está inundando. El precio es que ni él ni vos os enteráis. Los mensajes por conexión directa no se ven afectados, y el buzón se libera según caducan los blobs.",
              "El almacenamiento de adjuntos tiene tope y se llena. 512 MiB por contacto y 2 GiB en total: un contacto que insista verá sus envíos rechazados en vez de llenarte el disco, pero el rechazo es silencioso para él y visible para vos como aviso de cuota. Borrar la conversación libera el espacio; no hay purga automática por antigüedad.",
              "El listado del directorio de media es visible, aunque el contenido esté sellado y la base de datos cifrada: cuántos adjuntos tenés, de qué tamaño y de qué fecha.",
              "La clave privada sobrevive a desinstalar en iOS, Linux y Windows: vive en el almacén del sistema y esas plataformas no lo limpian. Para irte del todo usá el borrado de identidad de la app, que sí quita la clave del llavero; desinstalar por su cuenta no basta.",
              "Quien llama se identifica primero. Al abrir una conexión P2P, quien contesta no revela nada hasta haber verificado a la otra parte, pero la otra parte sí tiene que revelarse antes. Es una propiedad del patrón de handshake, no un descuido: no se le puede probar nada a una clave que todavía no conocés. Consecuencia práctica: alguien que genere una identidad desechable y complete el handshake confirma qué token está detrás de esa dirección IP.",
              "El límite de peticiones del relay depende de la configuración del operador. El relay sabe cobrar el límite a la dirección IP real detrás de un proxy inverso, pero solo si el operador le dice de qué proxies fiarse; sin esa lista ignora la cabecera y cobra a la dirección que conecta, que detrás de un proxy es una sola para todos. Hay techo global de disco —1 GiB por defecto, que rechaza en vez de desalojar nada ya aceptado—. Sin defensa contra inundación distribuida: un flood no lee mensajes ajenos, pero deja el relay inútil para los nuevos.",
              "El informe de abuso ya no sale por el portapapeles, pero en móvil no elegís dónde queda. El camino por defecto es guardarlo como fichero de texto, y en Linux y Windows sale el diálogo del sistema, así que la ruta la elegís vos. En iOS y Android no hay diálogo de guardado, de modo que el fichero va a una carpeta de la propia app: en iOS Documents/Informes, visible desde la app Archivos, y en Android la carpeta de la app en el almacenamiento compartido, que puede leer una computadora conectada por cable. Ese es el residual, y no lo escondemos: lo que sí hace el borrado de identidad es llevarse esa carpeta, para que un informe no sobreviva a la identidad que nombra. Copiar al portapapeles sigue existiendo como segunda acción explícita, debajo de una frase que dice qué es el portapapeles: quitarlo dejaba sin salida el caso de pegar el informe en un correo desde el teléfono y empujaba a algo peor, como una captura de pantalla. El informe se genera local y no lo recibe nadie.",
              "Un par que abre una sesión puede degradar el nodo. Basta con completar el handshake con una identidad propia —que no cuesta nada— para hacer que el dispositivo reserve memoria por lo que ese par decida mandar y para que la interfaz se quede procesándolo antes de poder rechazarlo. Los límites que hay están puestos en número de mensajes y de conexiones sin autenticar, no en bytes ni en trabajo. Es un problema de disponibilidad contra tu propio dispositivo, no de confidencialidad: nadie lee nada por esta vía. Pendiente antes de 1.0.",
              "Sin verificación de contactos en la app: ni números de seguridad ni aviso de cambio de clave.",
              "Sin protección contra capturas de pantalla en ninguna plataforma.",
              "Sin confidencialidad hacia adelante por mensaje.",
            ],
          },
        ],
        links: [
          { path: "/privacy", hash: "limitaciones", label: "Privacidad: lo que no prometemos" },
        ],
      },
      {
        id: "reportar",
        title: "Reportar una vulnerabilidad",
        blocks: [
          "info@elnerd.com — buzón atendido por el operador. Es una dirección de otro dominio, así que está confirmada desde el propio producto en esta página, en la política de privacidad y en https://encrypchat.com/.well-known/security.txt; si la encontraste en cualquier otro sitio, comprobala contra una de esas fuentes. Todavía no hay clave pública para reportes cifrados; si la necesitás, pedila en un primer correo sin detalles.",
          "Que esas fuentes sigan diciendo lo mismo, y que el security.txt no esté caducado, no depende de que alguien se acuerde: una comprobación automática corre en cada build y falla un mes antes de la fecha de caducidad, o en cuanto una de las copias se desvía. Un buzón de seguridad que dejó de existir es peor que no publicar ninguno, porque el que encuentra el fallo cree que avisó.",
          "Pedimos divulgación coordinada: contanos qué encontraste y dejanos un plazo razonable para corregirlo antes de publicarlo. No comprometemos tiempos de respuesta y no hay programa de recompensas. Sí publicamos los hallazgos y su estado junto al código, incluidos los que no hemos cerrado.",
          "Es el canal para fallos de seguridad del software. No es soporte, no es el buzón de privacidad y no sirve para denunciar a otro usuario: el informe de abuso de la app es local y no lo recibe nadie.",
        ],
        links: [{ path: "/privacy", hash: "seguridad", label: "Privacidad: reportar un fallo" }],
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
