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
      "Encrypchat native apps for Android, iOS, Linux, and Windows. Test builds via GitHub Releases or local dist/; see docs/phase-8.md.",
    h1: "Download",
    intro:
      "Native apps for Android, iOS, Linux (Fedora), and Windows. Public installers will ship on GitHub Releases when published — we do not link to URLs that are not live yet.",
    sourceNote:
      "Test builds: see docs/phase-8.md in the repository (make package → dist/ for Linux tarball and Android APK). iOS and Windows packages still need Mac / Windows hosts.",
  },
  faq: {
    metaTitle: "FAQ",
    metaDescription:
      "Frequently asked questions about Encrypchat: P2P encryption, zero-cloud storage, blind relays, device permissions, and platforms.",
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
        a: "Android, iOS, Linux (Fedora), and Windows are first-class targets. Linux and Android test packages are built into dist/ (see docs/phase-8.md); store links and GitHub Releases follow when publishing starts.",
      },
      {
        q: "How do I add a contact?",
        a: "You exchange cryptographic tokens (for example via QR). There is no central phone-number directory as the source of truth.",
      },
      {
        q: "What exactly does a blind relay see?",
        a: "The destination token, the size of the encrypted envelope, timestamps, the TTL, and the IP you connect from. Never the content or your keys. The envelope is deleted after delivery or when the TTL expires, and the relay is only involved if you configure one.",
      },
      {
        q: "Do calls go through your servers?",
        a: "No. Audio and video travel directly between the two devices with DTLS-SRTP encryption; there is no SFU and no Encrypchat media server. Public Google STUN servers help establish the connection and can see your IP address and call timing, not its content.",
      },
      {
        q: "Is my data encrypted on the device?",
        a: "Each message body and every media file is sealed with authenticated encryption under a key held in the operating system's secure store. The database file itself is not yet fully encrypted: conversation metadata is readable to anyone with device access. That work is still pending and we say so plainly.",
      },
      {
        q: "Does Encrypchat need access to my photos?",
        a: "On Android, no: the app requests no gallery permission. When you attach a photo, the system photo picker hands us only the image you chose, and on an older device without that picker the system file browser opens, which asks for no permission either. On iOS, the system may ask for photo library access when you pick the photo. On Linux and Windows the app uses the system file dialog. The photo is encrypted on your device before it leaves.",
      },
      {
        q: "How do I delete my identity and my data?",
        a: "By uninstalling the app: the local database and the media files go with it. The private key only disappears alongside the app on Android; on iOS, Linux, and Windows it stays in the system keyring and you have to delete that entry by hand. There is no \u201cdelete identity\u201d action inside the app yet.",
      },
      {
        q: "Do you use analytics or advertising?",
        a: "No. The app ships no metrics SDK, no crash reporting, and no advertising identifiers, and encrypchat.com uses no first-party cookies and no analytics.",
      },
    ],
  },
  legal: {
    relatedAria: "Related pages",
  },
  privacy: {
    metaTitle: "Privacy policy",
    metaDescription:
      "What data exists in Encrypchat and where it lives: identity and chats on your device, an optional blind relay that only sees ciphertext, P2P calls over public STUN. No accounts, no analytics.",
    h1: "Privacy policy",
    updated: "Last updated: 12 August 2026 · version 1.0 (pending counsel review)",
    updatedIso: "2026-08-12",
    summary:
      "Encrypchat has no accounts, keeps no copy of your conversations in the cloud, and runs no analytics or advertising. Your private key, your chats, and your media live on your device. The only thing a server can touch is ciphertext we cannot read: the sealed envelope an optional blind relay holds until delivery, and the public STUN servers that help set up a call and see IP addresses.",
    disclaimer:
      "This document describes what the software actually does today (pre-1.0). It is not legal advice, it has not yet been reviewed by a lawyer, and some fields are still pending from the operator. It must be finalized before publishing on Google Play or the App Store.",
    sections: [
      {
        id: "responsable",
        title: "Who publishes this policy",
        blocks: [
          "Encrypchat is a software project under development. The legal entity acting as data controller, its registered address, and its contact point are still to be designated.",
          "While that remains pending, this text stands as an honest technical disclosure of what the software does, not as a final policy for an app store submission.",
        ],
      },
      {
        id: "datos",
        title: "What data exists and where it lives",
        blocks: [
          "Everything below is created on your device and stays there. No copy sits on our servers.",
          [
            "Identity: an X25519 key pair generated locally. The private key is stored in the operating system's secure store: on Android, encrypted under a Keystore key inside the app's data directory; on iOS in the Keychain; on Linux in the libsecret keyring and on Windows in Credential Manager. The public key produces your public token \u201cec_\u2026\u201d, which is the only thing you share.",
            "Chats: stored in a local database inside the app's private directory. Each message body is sealed with authenticated encryption using a key held in the OS secure store.",
            "Media: photos you send and receive are stored as sealed encrypted files in the app's private storage; no plaintext bytes of the photo are left on disk. On mobile, the temporary copy the system picker creates is deleted as soon as the photo is sealed, and any leftovers from an earlier session are swept when the app starts. On Linux and Windows the picker returns your original file: we read it to encrypt the copy that is sent, and we neither modify nor delete it.",
            "Contacts: a local alias, the contact's token, and their public key. This is public material by design.",
            "Local metadata: who you talk to, timestamps, delivery status, and the media file path are stored unencrypted inside the database file. Full-file encryption is still pending. Anyone with physical access or root privileges on your device can reconstruct who you talked to and when, though not the content.",
          ],
          "There is no account, phone number, email address, or password tied to you on any server of ours.",
        ],
      },
      {
        id: "no-recopilamos",
        title: "What we do not collect",
        blocks: [
          [
            "No signup, no account: we never ask for a phone number, email, or name.",
            "No address book: we do not upload your contacts and we run no central phone directory.",
            "No analytics or telemetry in the app: no metrics SDK, no crash reporting, no advertising identifiers.",
            "No advertising, and no sale or sharing of data with third parties.",
            "No cloud backup: on Android, the system's automatic backup is disabled for the app.",
          ],
        ],
      },
      {
        id: "relay",
        title: "Blind relay (optional)",
        blocks: [
          "If your contact is offline, you can configure a relay to hold the encrypted message until they reconnect. It is off unless you configure it, and the relay may be operated by a third party, in which case their terms apply as well.",
          "What that relay can see:",
          [
            "The destination token the envelope is addressed to.",
            "The size in bytes of the encrypted envelope.",
            "Deposit time, delivery time, and time to live (TTL).",
            "The IP address your device connects from when depositing or polling.",
          ],
          "What it cannot see: the text, the photos, your private key, or the session key. The envelope is deleted after delivery or when the TTL expires.",
          "A known and honest limitation: on the relay path, the sender declared inside the envelope is not yet cryptographically authenticated. Someone who knows your public key could deposit a message that appears to come from another contact. This is documented as a blocker before operating public relays. For the same reason, call signaling never uses the relay.",
        ],
      },
      {
        id: "llamadas",
        title: "Audio and video calls",
        blocks: [
          "Audio and video travel directly between the two devices over WebRTC with DTLS-SRTP encryption. There is no SFU, mixer, or Encrypchat media server: the packets do not pass through us. Signaling (invite, SDP, and ICE) travels encrypted over the already established P2P channel and never over the relay.",
          "To discover each endpoint's public address, the app uses Google's public STUN servers (stun.l.google.com and stun1.l.google.com). Google can see your IP address and when you attempt a call, not its content.",
          "Also, on any P2P connection your contact sees your IP and you see theirs: that is inherent to talking directly, without an intermediary. There is no TURN server today, so calls may fail to connect on strict NAT networks.",
        ],
      },
      {
        id: "permisos",
        title: "Device permissions",
        blocks: [
          "The app requests each permission at the moment it is needed, and only for the stated purpose:",
          [
            "Microphone (Android RECORD_AUDIO, iOS NSMicrophoneUsageDescription): capture your voice when you start or accept a call.",
            "Camera (Android CAMERA, iOS NSCameraUsageDescription): capture your video on a video call.",
            "Audio routing and Bluetooth (Android MODIFY_AUDIO_SETTINGS, BLUETOOTH_CONNECT): route call audio to the speaker or a headset.",
            "Photo library on iOS (NSPhotoLibraryUsageDescription): the system may ask for access when you pick a photo to attach. The app only receives the image you selected.",
            "Internet: connect to your contact and, if you configured one, to the relay.",
          ],
          "On Android we request no gallery permission: the app no longer declares READ_MEDIA_IMAGES or READ_EXTERNAL_STORAGE. Attaching opens the system photo picker, which hands us only the photo you chose; the rest of your gallery stays out of our reach. On older devices without that picker, the system file browser opens instead: the experience changes, not the permission, because it asks for none either and also returns only the file you chose. On Linux and Windows the system file dialog works the same way.",
          "None of these permissions are used for background collection or profiling. The microphone and camera are only active during an ongoing call.",
        ],
      },
      {
        id: "sitio-web",
        title: "This website (encrypchat.com)",
        blocks: [
          "encrypchat.com is a static marketing and download site. It is not the chat, there is no login, and no user content is processed here.",
          [
            "No first-party cookies, no analytics, no third-party pixels.",
            "Fonts are served from our own domain: visiting the site does not trigger a request to Google Fonts.",
            "The hosting provider (Cloudflare Pages) records standard access logs (IP, user agent, timestamp) to serve the site and mitigate abuse, subject to their own policy.",
          ],
          "If we ever add analytics, it will be announced on this page before it is enabled.",
        ],
      },
      {
        id: "terceros",
        title: "Third parties involved",
        blocks: [
          [
            "Cloudflare: website hosting.",
            "Google STUN: call connectivity (sees IP and call timing).",
            "The relay operator you choose, if you enable offline delivery.",
            "Google Play and the App Store once the app is published: they handle the download and their own account data, outside our reach.",
          ],
          "Encrypchat does not send your data to any other third party.",
        ],
      },
      {
        id: "retencion",
        title: "Retention and deletion",
        blocks: [
          [
            "On your device: messages and media stay until you delete them or uninstall the app. Deleting something on your device does not delete it from your contact's device.",
            "On the relay: the encrypted envelope is deleted after delivery or when its TTL expires, whichever comes first.",
            "On uninstall: the local database, the media files, and the rest of the app's private directory are gone. There is no cloud copy and no account recovery, so your conversations are lost irreversibly. Export your contacts from the app first if you want to keep them.",
            "The private key, however, only leaves with the app on Android, where it is stored inside the app's data directory. On iOS, Linux, and Windows it stays in the system keyring (Keychain, libsecret, and Credential Manager), which by design survives uninstalling an application. That key on its own opens no conversation — the messages and media are no longer on the device: it is a leftover identity, not an archive of your chats. To remove it completely, delete the Encrypchat entry from the system keyring by hand.",
            "There is no \u201cdelete identity\u201d action inside the app yet. It has been assessed and deliberately deferred: wiping the material is simple, but keeping the app standing afterwards means reworking the session lifecycle, and we would rather not ship a button that can leave it in an inconsistent state. Until then, the route is to uninstall and, on iOS, Linux, and Windows, clear that keyring entry.",
          ],
        ],
      },
      {
        id: "derechos",
        title: "Your rights",
        blocks: [
          "Because we run no content server, we hold no copy of your messages to hand over, correct, or erase: you exercise those rights directly on your device, where you have full control over the data.",
          "Access, rectification, erasure, objection, and portability requests (GDPR and equivalents) will be handled through the contact channel once it is live. In practice, the answer will almost always be that we do not hold the data.",
          "Exercising erasure today means uninstalling the app, which removes chats and media, and on iOS, Linux, and Windows also deleting the Encrypchat entry from the system keyring, where the private key remains. The app does not yet ship an action of its own for this \u2014 see \u201cRetention and deletion\u201d for the detail.",
        ],
      },
      {
        id: "menores",
        title: "Children",
        blocks: [
          "Encrypchat is not directed at children under 13 and does not knowingly collect data from them. The final age rating for each store is still to be completed along with the rest of the submission paperwork.",
        ],
      },
      {
        id: "limitaciones",
        title: "What this policy does not promise",
        blocks: [
          "We would rather say it up front:",
          [
            "We do not claim \u201czero metadata\u201d: the relay sees destination, size, and timing, and STUN sees your IP.",
            "We do not claim \u201cimpossible to intercept\u201d or \u201c100% private\u201d. Encryption reduces risk; it does not remove it.",
            "End-to-end encryption does not protect a compromised device, a screenshot, or operating-system backups you make yourself.",
            "The local database file is not yet fully encrypted: conversation metadata is readable with device access.",
            "Uninstalling does not delete the private key on iOS, Linux, and Windows: it stays in the system keyring until you remove that entry by hand.",
            "The clipboard is not ours: exporting a contact, copying your token, or saving an abuse report all go through the system clipboard, which keeps a history on Windows and can be read by other apps on Android.",
            "The operating system keeps a thumbnail of each app's last screen for the task switcher: if a photo was open, it can sit there until it is refreshed.",
            "The software is pre-1.0 and has not passed an independent external security audit.",
          ],
        ],
      },
      {
        id: "cambios",
        title: "Changes to this policy",
        blocks: [
          "The last update date appears at the top. Material changes will be published on this page and, once public releases exist, in their release notes.",
        ],
      },
      {
        id: "contacto",
        title: "Contact and jurisdiction",
        blocks: [
          "Pending from the operator: the responsible legal entity, its address, a privacy contact address, and the governing law.",
          "There is no working privacy mailbox today. The address shown in the earlier draft of this page has been removed because it was never activated, and we do not publish addresses that do not work.",
        ],
      },
    ],
  },
  terms: {
    metaTitle: "Terms of use",
    metaDescription:
      "Encrypchat terms of use: P2P client software under development, provided as-is, with no accounts, no key recovery, and no hosted messaging service.",
    h1: "Terms of use",
    updated: "Last updated: 12 August 2026 · version 1.0 (pending counsel review)",
    updatedIso: "2026-08-12",
    summary:
      "Encrypchat is client software under development, provided as-is. We do not run a cloud messaging service: we cannot read, moderate, recover, or restore your conversations.",
    disclaimer:
      "This document is not legal advice, it has not yet been reviewed by a lawyer, and some fields are still pending from the operator. It must be finalized before publishing on Google Play or the App Store.",
    sections: [
      {
        id: "aceptacion",
        title: "Acceptance",
        blocks: [
          "By downloading, installing, or using Encrypchat you accept these terms. If you do not agree, do not use the software.",
        ],
      },
      {
        id: "servicio",
        title: "What the service is and is not",
        blocks: [
          "Encrypchat is client software for encrypted peer-to-peer messaging. Every install acts as both a client and a local node: it is your devices that connect to each other.",
          "We do not sell or operate a hosted messaging service. The only optional infrastructure is a blind relay for offline delivery, which you may or may not configure, and the public STUN servers that help establish a call.",
        ],
      },
      {
        id: "estado",
        title: "State of the software",
        blocks: [
          "Encrypchat is pre-1.0 and under active development. As a result:",
          [
            "Features may change, break, or disappear between versions.",
            "There is no guarantee of message delivery or availability; data loss is possible.",
            "The binaries available today are test builds for manual installation, not store releases.",
            "The software has not passed an independent external security audit.",
          ],
        ],
      },
      {
        id: "claves",
        title: "Your keys are your responsibility",
        blocks: [
          "Your identity is a key pair that exists only on your device. There is no account recovery, no password reset, and no server-side backup.",
          "Losing the device, clearing the app data, or uninstalling irreversibly destroys your conversation history, and there is no way to get it back. The private key only leaves with the app on Android: on iOS, Linux, and Windows it stays in the system keyring until you delete that entry by hand. Protect the device with the operating system lock and make a conscious decision about which backups you keep.",
        ],
      },
      {
        id: "uso",
        title: "Acceptable use",
        blocks: [
          [
            "Do not use Encrypchat for activities that are illegal in your jurisdiction, for harassment, or to distribute malware or spam.",
            "Do not abuse any optional infrastructure we operate: rate limits and quotas may apply, and circumventing them is not allowed.",
            "Do not attempt to impersonate another user or interfere with availability for others.",
          ],
          "We may refuse abusive use of any infrastructure we operate. What we cannot do is block a direct conversation between two devices: the architecture does not allow it.",
        ],
      },
      {
        id: "contenido",
        title: "Content and moderation",
        blocks: [
          "Content is created and transmitted by users. We do not host it in readable form, we cannot read it, and therefore we cannot moderate it, filter it, or hand it to a third party. Legal responsibility for what you send is yours.",
          "Note that on a peer-to-peer connection your IP address is visible to your contact, just as theirs is to you.",
        ],
      },
      {
        id: "terceros",
        title: "Third-party services",
        blocks: [
          "Any relay you configure (your own or someone else's) and the public STUN servers are governed by their own terms and policies. We are not responsible for their availability, their log retention, or their service changes.",
        ],
      },
      {
        id: "propiedad",
        title: "Intellectual property and licensing",
        blocks: [
          "The Encrypchat name and logo belong to the project. The source code is currently under \u201call rights reserved\u201d, with the final license still to be decided: no redistribution or derivative-work permission is granted until it is published.",
          "The application is distributed free of charge and contains no in-app purchases or subscriptions.",
        ],
      },
      {
        id: "exportacion",
        title: "Cryptography and export control",
        blocks: [
          "Encrypchat includes standard, widely available cryptography (X25519, ChaCha20-Poly1305, and DTLS-SRTP for calls). You are responsible for complying with the cryptography import, use, and export rules that apply in your jurisdiction.",
          "The formal export declaration required by app stores is still to be completed before publication.",
        ],
      },
      {
        id: "garantias",
        title: "No warranties",
        blocks: [
          "The software is provided \u201cas is\u201d and \u201cas available\u201d, without express or implied warranties of merchantability, fitness for a particular purpose, or freedom from defects.",
          "Encryption reduces risk; it does not remove it. Device security, physical access, malware, and network metadata analysis remain real threats.",
        ],
      },
      {
        id: "responsabilidad",
        title: "Limitation of liability",
        blocks: [
          "To the maximum extent permitted by applicable law, we are not liable for indirect, incidental, or consequential damages, nor for loss of data, messages, or identity arising from use of the software.",
          "The monetary liability cap is still to be set alongside the legal entity.",
        ],
      },
      {
        id: "cambios",
        title: "Changes and termination",
        blocks: [
          "We may update these terms and withdraw or modify any optional infrastructure. Software already installed keeps working device-to-device even if that infrastructure disappears.",
        ],
      },
      {
        id: "ley",
        title: "Governing law and contact",
        blocks: [
          "Pending from the operator: legal entity, governing law, competent forum, and contact channel. Until then, no contact address is published.",
        ],
      },
    ],
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
