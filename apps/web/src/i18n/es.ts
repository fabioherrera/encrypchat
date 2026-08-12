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
      "El historial y los medios se guardan en tu teléfono o computadora. No operamos un buzón de mensajes que pueda leer tus conversaciones.",
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
      "Descargá Encrypchat para Android, iOS, Linux (Fedora) y Windows. Las builds llegan pronto — volvé cuando el empaquetado esté listo.",
    h1: "Descargar",
    intro:
      "Apps nativas para cada plataforma de primera clase. Los instaladores aparecerán aquí cuando avance el empaquetado de la Fase 8.",
    sourceNote:
      "¿Preferís compilar desde el código mientras faltan binarios? Consultá el roadmap en la documentación del repositorio público.",
  },
  faq: {
    metaTitle: "FAQ",
    metaDescription:
      "Preguntas frecuentes sobre Encrypchat: cifrado P2P, almacenamiento zero-cloud, relays ciegos y plataformas.",
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
        a: "Android, iOS, Linux (Fedora) y Windows son objetivos de primera clase. Los enlaces de descarga aparecen cuando haya instaladores.",
      },
      {
        q: "¿Cómo agrego un contacto?",
        a: "Intercambiás tokens criptográficos (por ejemplo con QR). No hay un directorio telefónico central como fuente de verdad.",
      },
    ],
  },
  privacy: {
    metaTitle: "Privacidad",
    metaDescription:
      "Resumen de privacidad de Encrypchat: chats en el dispositivo, E2EE y relays ciegos opcionales que solo ven cifrado.",
    h1: "Privacidad",
    stub: "Borrador de política — finalizar con asesoría legal antes del lanzamiento en stores (Fase 9).",
    collectTitle: "Qué queremos recopilar",
    collectBody:
      "Encrypchat está diseñado para que el contenido de los mensajes permanezca en tus dispositivos. No operamos un buzón en la nube de chats legibles.",
    deviceTitle: "En tu dispositivo",
    deviceBody:
      "Claves de identidad, contactos e historial se guardan en local. Protegé tu dispositivo con bloqueo del SO y backups en los que confíes.",
    relayTitle: "Relays ciegos",
    relayBody:
      "Si usás un relay para entrega offline, ese servicio puede procesar cifrado dirigido a tu token, metadatos de entrega necesarios para enrutar el blob y temporizadores TTL. Los relays no están pensados para descifrar contenido.",
    siteTitle: "Este sitio",
    siteBody:
      "encrypchat.com puede usar logs estándar de hosting (IP, user agent) vía CDN/host. Divulgaremos cualquier cookie de analítica antes de activarla.",
    contactTitle: "Contacto",
    contactBody:
      "Solicitudes de privacidad: privacy@encrypchat.com (buzón por activar).",
  },
  terms: {
    metaTitle: "Términos",
    metaDescription:
      "Borrador de términos de uso de Encrypchat: software tal cual durante el desarrollo; sin garantía de entrega ininterrumpida.",
    h1: "Términos de uso",
    stub: "Borrador de términos — finalizar con asesoría legal antes del lanzamiento en stores (Fase 9).",
    serviceTitle: "Servicio",
    serviceBody:
      "Encrypchat ofrece software cliente para mensajería cifrada de igual a igual. Infraestructura opcional (relays ciegos o STUN/TURN) puede ayudar a la conectividad sin ofrecer un archivo legible de mensajes.",
    securityTitle: "Sin promesa de seguridad absoluta",
    securityBody:
      "El cifrado reduce el riesgo; no hace imposible el compromiso. La seguridad del extremo, el acceso físico, el malware y los metadatos de red siguen siendo amenazas reales.",
    availabilityTitle: "Disponibilidad",
    availabilityBody:
      "Durante el desarrollo, funciones y binarios pueden estar incompletos. Relays y ayudas de descubrimiento pueden no estar disponibles o tener límites de tasa.",
    useTitle: "Uso aceptable",
    useBody:
      "No uses Encrypchat para violar la ley aplicable. Podemos rechazar el uso abusivo de cualquier infraestructura que operemos.",
  },
  redirect: {
    message: "Redirigiendo a Encrypchat…",
    link: "Continuar en inglés",
  },
};

export default es;
