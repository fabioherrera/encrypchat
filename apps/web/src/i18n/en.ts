import type { Dictionary } from "./types";

const en: Dictionary = {
  meta: {
    titleDefault: "Encrypchat — P2P encrypted chat, zero-cloud",
    titleTemplate: "%s · Encrypchat",
    description:
      "Encrypchat is a peer-to-peer encrypted messenger. Chats and media stay on your device. Optional blind relays hold only ciphertext until delivery.",
    keywords: [
      "Encrypchat",
      "encrypted chat",
      "P2P messaging",
      "zero-cloud",
      "E2EE",
      "decentralized chat",
    ],
    ogLocale: "en_US",
  },
  nav: {
    features: "Features",
    download: "Download",
    faq: "FAQ",
    cta: "Get the app",
    primaryAria: "Primary",
    langSwitcherAria: "Language",
  },
  footer: {
    note: "End-to-end encrypted P2P messaging. Optional blind relays store only ciphertext until delivery — not your readable chats.",
    privacy: "Privacy",
    terms: "Terms",
    faq: "FAQ",
    download: "Download",
    aria: "Footer",
  },
  platforms: {
    android: "Android",
    ios: "iOS",
    linux: "Linux (Fedora)",
    windows: "Windows",
    comingSoon: "Coming soon",
  },
  home: {
    heroAria: "Hero",
    lead: "Peer-to-peer encrypted chat on your device — not a cloud inbox we can read.",
    ctaDownload: "Download",
    ctaFeatures: "How it works",
    privacyTitle: "Built for device-local privacy",
    privacyP1:
      "Each install is a client and a local node. Identity is a cryptographic token you share (QR or paste) — not a phone-number directory we control. When someone is offline, an optional blind relay can hold sealed ciphertext until they reconnect; relays cannot read message contents.",
    privacyP2Before: "In the app you will see",
    privacyP2P2p: "P2P",
    privacyP2Mid: "when peers connect directly,",
    privacyP2Relay: "relay",
    privacyP2After:
      "when sealed ciphertext waits offline, and offline when the device cannot reach the network.",
    platformsTitle: "Platforms",
    softwareDescription:
      "Peer-to-peer encrypted messenger. Messages stay on your devices; optional blind relays hold ciphertext only.",
  },
  features: {
    metaTitle: "Features",
    metaDescription:
      "P2P encrypted messaging, device-local storage, cryptographic tokens, and optional blind relays for Encrypchat.",
    h1: "Features",
    intro: "Encrypchat is designed so readable chats never sit in our cloud.",
    e2eeTitle: "End-to-end encryption",
    e2eeBody:
      "Messages are encrypted on your device for the recipient's key before they leave. Only the intended device can decrypt them.",
    p2pTitle: "Peer-to-peer first",
    p2pBody:
      "When both sides are online, traffic prefers a direct device-to-device path. That cuts intermediaries for live chat, media, and calls.",
    zeroCloudTitle: "Zero-cloud content",
    zeroCloudBody:
      "Chat history and media are stored locally on your phone or computer. We do not operate a message inbox that can read your conversations.",
    relayTitle: "Blind relay (optional, offline)",
    relayBodyBefore: "If the recipient is offline, a relay may temporarily hold",
    relayCiphertext: "ciphertext",
    relayBodyAfter:
      "addressed to their token, then delete it after delivery. Relays are not a cloud backup of your chat history and cannot decrypt contents.",
    tokenTitle: "Token identity",
    tokenBody:
      "Contacts are cryptographic tokens (from public keys), exchanged via QR or paste. There is no central phone-number directory as the source of truth.",
    cta: "Get Encrypchat",
  },
  download: {
    metaTitle: "Download",
    metaDescription:
      "Download Encrypchat for Android, iOS, Linux (Fedora), and Windows. Builds are coming soon — check back as packaging lands.",
    h1: "Download",
    intro:
      "Native apps for every first-class platform. Installers will appear here as Phase 8 packaging lands.",
    sourceNote:
      "Prefer building from source while binaries are pending? See the project roadmap in the public repository documentation.",
  },
  faq: {
    metaTitle: "FAQ",
    metaDescription:
      "Frequently asked questions about Encrypchat: P2P encryption, zero-cloud storage, blind relays, and platforms.",
    h1: "FAQ",
    items: [
      {
        q: "Is Encrypchat end-to-end encrypted?",
        a: "Yes. Messages are encrypted on the sender device for the recipient's key. Readable plaintext is meant to exist only on the endpoints.",
      },
      {
        q: "Do you store my chats in the cloud?",
        a: "No. Chat content is stored on your devices. That is what we mean by zero-cloud content.",
      },
      {
        q: "What is a blind relay?",
        a: "An optional helper for offline delivery. It can hold sealed ciphertext for your token until you come online, then delete it. It cannot decrypt message contents.",
      },
      {
        q: "Which platforms are supported?",
        a: "Android, iOS, Linux (Fedora), and Windows are first-class targets. Download links appear when installers are ready.",
      },
      {
        q: "How do I add a contact?",
        a: "You exchange cryptographic tokens (for example via QR). There is no central phone-number directory as the source of truth.",
      },
    ],
  },
  privacy: {
    metaTitle: "Privacy",
    metaDescription:
      "Encrypchat privacy overview: device-local chats, E2EE, and optional blind relays that only see ciphertext.",
    h1: "Privacy",
    stub: "Stub policy — finalize with counsel before store launch (Phase 9).",
    collectTitle: "What we want to collect",
    collectBody:
      "Encrypchat is designed so message content stays on your devices. We do not operate a cloud mailbox of readable chats.",
    deviceTitle: "On your device",
    deviceBody:
      "Identity keys, contacts, and message history are stored locally. Protect your device with OS lock screens and backups you trust.",
    relayTitle: "Blind relays",
    relayBody:
      "If you use a relay for offline delivery, that service may process ciphertext addressed to your token, delivery metadata necessary to route the blob, and TTL timers. Relays are not intended to decrypt content.",
    siteTitle: "This website",
    siteBody:
      "encrypchat.com may use standard hosting logs (IP, user agent) via the CDN/host. We will disclose any analytics cookies before enabling them.",
    contactTitle: "Contact",
    contactBody:
      "Privacy requests: privacy@encrypchat.com (mailbox to be activated).",
  },
  terms: {
    metaTitle: "Terms",
    metaDescription:
      "Encrypchat terms of use stub: software provided as-is during development; no guarantee of uninterrupted delivery.",
    h1: "Terms of use",
    stub: "Stub terms — finalize with counsel before store launch (Phase 9).",
    serviceTitle: "Service",
    serviceBody:
      "Encrypchat provides client software for encrypted peer-to-peer messaging. Optional infrastructure (such as blind relays or STUN/TURN) may assist connectivity without providing a readable message archive.",
    securityTitle: "No absolute security promise",
    securityBody:
      "Encryption reduces risk; it does not make compromise impossible. Endpoint security, physical access, malware, and network metadata remain real threats.",
    availabilityTitle: "Availability",
    availabilityBody:
      "During development, features and binaries may be incomplete. Relays and discovery helpers may be unavailable or rate-limited.",
    useTitle: "Acceptable use",
    useBody:
      "Do not use Encrypchat to violate applicable law. We may refuse abusive use of any infrastructure we operate.",
  },
  redirect: {
    message: "Redirecting to Encrypchat…",
    link: "Continue in English",
  },
  demo: {
    peerName: "Maria Ruiz",
    diegoName: "Diego Soto",
    anaName: "Ana Lopez",
    chatsLabel: "Chats",
    statusOnline: "P2P · online",
    dayToday: "Today",
    e2eeBanner: "E2EE · on this device",
    draftText: "I'm downstairs",
    videoCallHint: "Encrypted on this device",
    videoCallBadge: "P2P · 02:14",
    videoCallYou: "You",
    yesterday: "Yesterday",
    mondayShort: "Mon",
    m1: "Still on for coffee at the corner place at 10?",
    m2: "Yep. Is the terrace open?",
    m3Caption: "Just walked by — terrace is free",
    m3Alt: "Cafe exterior",
    m4Caption: "Perfect, I'll grab that table",
    m4Alt: "Cafe table",
    m5Caption: "Heading out — this is the way",
    m5Alt: "Street toward the cafe",
    m6: "Better on video for a sec — I lost the map",
    callLabel: "P2P video call",
    callDetail: "2:14 · encrypted on device",
    s1: "Coming in through the terrace?",
    s2: "In 5 — around the corner",
    s3Caption: "Table free",
    diegoPreview: "See you on Fedora",
    anaPreview: "QR key ready",
  },
};

export default en;
