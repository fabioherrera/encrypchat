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
    security: "Security",
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
    apk: "APK arm64",
    rpm: "Fedora RPM",
    tarball: "portable tar.gz",
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
    platformsNote:
      "We are in testing. Android and Linux have a test build; GitHub asks you to sign in while the repo is private. iOS and Windows have no package here yet.",
    testingBadge: "Testing",
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
      "Chat history and media are stored locally on your phone or computer, in a SQLCipher-encrypted database with message bodies sealed on top. We do not operate a message inbox that can read your conversations.",
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
    metaTitle: "Download — testing",
    metaDescription:
      "Encrypchat is in testing. Unsigned Android APK and Linux RPM or tar.gz. iOS and Windows not yet. The repo is private: GitHub asks you to sign in.",
    h1: "Download",
    testingBadge: "Testing",
    testingLead:
      "We are in testing. These installers are for trying the app on real devices. They are not a store build and not a public launch.",
    intro:
      "Android and Linux have a package. iOS needs a Mac; Windows is built on a Windows machine.",
    privateNote:
      "The repository is private: GitHub will ask you to sign in. When the app is ready, the repo goes public and these same links stop asking for an account.",
    unsignedNote:
      "Nothing is signed. Fedora will say so on install. The APK uses the debug key: it is for sideload, not Play Store, and changing that key later forces an uninstall — which on Android does wipe the local database.",
    checksums: "Check SHA-256",
    releasePage: "Notes for this batch",
    sourceNote:
      "Windows: on the machine, scripts\\package-windows.ps1. iOS: needs a macOS host (scripts/package-ios.sh). The code is in the same repository.",
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
        a: "Android, iOS, Linux (Fedora), and Windows are first-class targets. There is an Android APK and a Linux RPM or tar.gz as test builds on GitHub Releases. iOS and Windows have no package on that list yet. Store links come when publishing starts.",
      },
      {
        q: "How do I add a contact?",
        a: "The other person scans the QR on My token with the camera (on Linux and Windows you paste the export, or read a photo of the QR). There is no central phone-number directory as the source of truth.",
      },
      {
        q: "Can someone who is not my contact message me?",
        a: "Yes, if they have your token — but it does not land in your chats: it goes to a bounded requests inbox. Text only, up to 5 messages of 4 KiB per sender and 20 senders at a time, with no attachments, no calls, and no notification. Accepting the request is what creates the contact; you can also discard it or block the token.",
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
        a: "Yes, in two layers. The database file is fully encrypted with SQLCipher (AES-256) under a key derived from the one held in the operating system's secure store, and on top of that every message body and every media file is sealed with authenticated encryption. That protects the file when someone reads it off the disk: a stolen laptop, a powered-off phone, a recovered backup, or another account on the same system. What it does not protect is an unlocked device with the keyring accessible — whoever reads the key opens the database, and that boundary is the system lock screen, not our encryption layer — nor the media directory listing: each file's contents are sealed, but how many there are, their sizes, and their dates are filesystem metadata.",
      },
      {
        q: "Does Encrypchat need access to my photos?",
        a: "On Android, no: the app requests no gallery permission. When you attach a photo, the system photo picker hands us only the image you chose, and on an older device without that picker the system file browser opens, which asks for no permission either. On iOS, the system may ask for photo library access when you pick the photo. On Linux and Windows the app uses the system file dialog. The photo is encrypted on your device before it leaves.",
      },
      {
        q: "How do I delete my identity and my data?",
        a: "From inside the app, with \u201cdelete identity\u201d: it removes the key from the system keyring first and then the database and the attachments, so there is nothing left to clean up by hand. If it is interrupted, it resumes on the next launch before anything else opens. What that deletion cannot do is overwrite the bytes: they remain as ciphertext without a key, not as blank space, and a system backup taken before the deletion may still hold the key. Simply uninstalling also takes the database and the media files, but on iOS, Linux, and Windows it leaves the private key in the system keyring until you delete that entry by hand.",
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
      "What data exists in Encrypchat and where it lives: chats on your device, in an encrypted database. Optional blind relay, P2P calls, no accounts, no analytics.",
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
            "Media: photos you send and receive are stored as sealed encrypted files in the app's private storage; no plaintext bytes of the photo are left on disk. On mobile, the temporary copy the system picker creates is deleted as soon as the photo is sealed, and any leftovers from an earlier session are swept when the app starts. On Linux and Windows the picker returns your original file: we read it to encrypt the copy that is sent, and we neither modify nor delete it. Each stored file's contents are sealed, but the directory listing is not: how many attachments you have, their sizes, and their dates are filesystem metadata.",
            "Contacts: a local alias, the contact's token, and their public key. This is public material by design.",
            "Abuse reports you save: the app writes them as a text file where you tell it to and, on mobile, into a folder of its own. That file sits outside the encrypted database, carries your token and the reported token, and nobody receives it: it stays on your device until you delete it. If it landed in the app's folder, deleting your identity takes it; if you saved it somewhere else, it is yours.",
            "Requests from strangers: someone who has your token but is not in your contacts can write to you, and that lands in a requests inbox kept apart from your chats — text only, up to 5 messages of 4 KiB per sender and 20 senders at a time, no attachments, no calls, and no notification. What is stored is the token, the public key when the route carries one, the dates, and the counter. Accepting a request is what creates the contact; discarding it deletes their messages.",
            "Local metadata: who you talk to, timestamps, delivery status, and the media file path live inside the database file, which is fully encrypted with SQLCipher (AES-256) under a key derived from the one in the OS secure store. A file taken off the disk — a stolen laptop, a powered-off phone, a recovered backup, another account on the system — cannot be read without that key. An unlocked device with the keyring accessible is a different story: whoever obtains the key opens the database and sees both that metadata and the content. That boundary is set by the operating system lock.",
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
          "On authorship, which earlier versions of this page listed as an open limitation: the sender is cryptographically authenticated, on both routes. In the envelope that goes through a relay, the sender is bound to the content, so the token a message is attributed to comes out of the ciphertext itself; the declared sender field that used to travel with it no longer exists in the format. On a direct connection, opening a session requires proving possession of the private key. Holding your public key — it travels in the contact card you share — is no longer enough to present themselves as you.",
          "That is what makes blocking work: the decision is taken against that authenticated identity rather than a value the sender picks, and it covers alternative encodings of the same key, which used to yield a different token and were a way back in. What blocking cannot prevent is the same person generating a new identity, nor — being local and one-sided — them continuing to deposit into a mailbox your device no longer drains. What does remain from this section is the metadata above: you cannot verify from outside that a relay honors the TTL or does not log that correlation, so a direct connection is still preferable.",
        ],
      },
      {
        id: "llamadas",
        title: "Audio and video calls",
        blocks: [
          "Audio and video travel directly between the two devices over WebRTC with DTLS-SRTP encryption. There is no SFU, mixer, or Encrypchat media server: the packets do not pass through us. Signaling (invite, SDP, and ICE) travels encrypted over the already established P2P channel and never over the relay.",
          "To discover each endpoint's public address, the app uses Google's public STUN servers (stun.l.google.com and stun1.l.google.com). Google can see your IP address and when you attempt a call, not its content.",
          "Also, on any P2P connection your contact sees your IP and you see theirs: that is inherent to talking directly, without an intermediary. There is no TURN server today, so calls may fail to connect on strict NAT networks.",
          "About who is calling: the peer's identity is verified when the connection is established, so an incoming call does come from the owner of that token. An invitation from a token that is not in your contacts is dropped without ringing, and the microphone and camera only turn on if you accept. Blocking someone mid-call ends the call.",
          "The honest residual here is not about authorship, it is about exposure: when the connection is established, the caller identifies itself first to the party answering. Whoever answers reveals nothing until it has verified the other side, but someone who generates a throwaway identity and completes the exchange can confirm that a given token is behind that IP address. Closing it entirely would require dialing with the destination's public key rather than its token, which is a hash.",
        ],
      },
      {
        id: "permisos",
        title: "Device permissions",
        blocks: [
          "The app requests each permission at the moment it is needed, and only for the stated purpose:",
          [
            "Microphone (Android RECORD_AUDIO, iOS NSMicrophoneUsageDescription): capture your voice when you start or accept a call.",
            "Camera (Android CAMERA, iOS NSCameraUsageDescription): scan a contact QR code, and capture your video on a video call. In both cases the frames are processed on this device and are not uploaded to any Encrypchat server. On Linux and Windows there is no live camera for the QR: it is read from an image, or you paste the export.",
            "Audio routing and Bluetooth (Android MODIFY_AUDIO_SETTINGS, BLUETOOTH_CONNECT): route call audio to the speaker or a headset.",
            "Photo library on iOS (NSPhotoLibraryUsageDescription): the system may ask for access when you pick a photo to attach. The app only receives the image you selected.",
            "Internet: connect to your contact and, if you configured one, to the relay.",
          ],
          "On Android we request no gallery permission: the app no longer declares READ_MEDIA_IMAGES or READ_EXTERNAL_STORAGE. Attaching opens the system photo picker, which hands us only the photo you chose; the rest of your gallery stays out of our reach. On older devices without that picker, the system file browser opens instead: the experience changes, not the permission, because it asks for none either and also returns only the file you chose. On Linux and Windows the system file dialog works the same way.",
          "None of these permissions are used for background collection or profiling. The microphone is only active during a call. The camera is active during a video call and while the scan-a-contact screen is open; leaving that screen turns it off.",
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
            "On your device: messages and media stay until you delete them, until you use \u201cdelete identity\u201d, or until you uninstall the app. Deleting something on your device does not delete it from your contact's device.",
            "On the relay: the encrypted envelope is deleted after delivery or when its TTL expires, whichever comes first.",
            "On uninstall: the local database, the media files, and the rest of the app's private directory are gone. There is no cloud copy and no account recovery, so your conversations are lost irreversibly. Export your contacts from the app first if you want to keep them.",
            "The private key, however, only leaves with the app on Android, where it is stored inside the app's data directory. On iOS, Linux, and Windows it stays in the system keyring (Keychain, libsecret, and Credential Manager), which by design survives uninstalling an application. That key on its own opens no conversation — the messages and media are no longer on the device: it is a leftover identity, not an archive of your chats. To remove it completely without touching the keyring by hand, use \u201cdelete identity\u201d inside the app before uninstalling.",
            "With \u201cdelete identity\u201d, inside the app: it removes the key from the system keyring first and then the database and the attachments. If it is interrupted, it resumes on the next launch before anything else opens. If the system refuses to remove a file \u2014 which happens on Windows when another process holds it open \u2014 the app tells you how many were left instead of calling it done. What it cannot do is overwrite the bytes: they remain as ciphertext without a key, not as blank space, and a system backup taken before the deletion may still hold the key.",
            "That deletion also takes the abuse reports the app filed in its own folder, which are plaintext carrying your token next to the reported one. What it does not reach is what you took elsewhere: a report saved through the system dialog, or an exported contact, sit where you put them, outside anything the app can see, and you delete them like any other file of yours.",
          ],
        ],
      },
      {
        id: "derechos",
        title: "Your rights",
        blocks: [
          "Because we run no content server, we hold no copy of your messages to hand over, correct, or erase: you exercise those rights directly on your device, where you have full control over the data.",
          "Access, rectification, erasure, objection, and portability requests (GDPR and equivalents) will be handled through the contact channel once it is live. In practice, the answer will almost always be that we do not hold the data.",
          "Exercising erasure means using \u201cdelete identity\u201d inside the app: it removes the key from the system keyring and then the database and the attachments from this device. Uninstalling also takes chats and media, but on iOS, Linux, and Windows it leaves the private key in the keyring until you delete that entry by hand \u2014 see \u201cRetention and deletion\u201d for the detail.",
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
            "Encrypting the database file does not protect an unlocked device: whoever can read the key from the keyring opens the database. That boundary is set by the operating system lock.",
            "The media directory listing stays visible even though each file's contents are sealed: how many attachments there are, their sizes, and their dates.",
            "The sender is authenticated on both routes and a public key is no longer enough to impersonate you, but we do not promise anonymity: the relay sees network metadata, the caller identifies itself first to the party answering, and what sits on disk depends on the device not being compromised.",
            "Anyone holding your token can leave you a text request without being a contact: it goes to a bounded inbox, with no attachments and no calls, and without alerting you — but there is no way to stop them taking one of those slots, nor to know that your token reached them from who you think.",
            "Uninstalling does not delete the private key on iOS, Linux, and Windows: it stays in the system keyring until you remove that entry by hand, or until you use \u201cdelete identity\u201d inside the app, which does remove it. Neither route overwrites the bytes already on disk: they remain as ciphertext without a key.",
            "The clipboard is not ours: exporting a contact or copying your token go through the system clipboard, which keeps a history on Windows and can be read by other apps on Android. The abuse report no longer goes through it — it is saved as a file — and copying it is a second action you choose.",
            "The operating system keeps a thumbnail of each app's last screen for the task switcher: if a photo was open, it can sit there until it is refreshed.",
            "The software is pre-1.0 and has not passed an independent external security audit.",
          ],
        ],
        links: [
          { path: "/security", hash: "limitaciones", label: "Threat model: known limitations" },
        ],
      },
      {
        id: "seguridad",
        title: "Reporting a security bug",
        blocks: [
          "If you find a vulnerability in Encrypchat, write to info@elnerd.com.",
          "We publish that address on encrypchat.com, and only here: this page, the security page, and https://encrypchat.com/.well-known/security.txt. If you found it anywhere else, check it against one of those three before writing.",
          "We ask for coordinated disclosure: tell us what you found and leave us a reasonable window to fix it before publishing. We do not commit to response times and there is no bug bounty program. We do publish findings and the state they are in, including the ones still open.",
          "This is the channel for security bugs in the software. It is not support, it is not the privacy mailbox, and it is not for reporting another user: the app's abuse report is local and nobody receives it.",
          "Before writing, the threat model is worth reading: it says what the product protects, what it does not, and which limitations we already know about and have published.",
        ],
        links: [{ path: "/security", hash: "reportar", label: "Threat model: how to report" }],
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
          "For security bugs there is a published address: see \u201cReporting a security bug\u201d, above.",
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
          "Losing the device, clearing the app data, using \u201cdelete identity\u201d, or uninstalling irreversibly destroys your conversation history, and there is no way to get it back. \u201cDelete identity\u201d also removes the private key from the system keyring; if you only uninstall, on iOS, Linux, and Windows that key stays there until you delete the entry by hand. Protect the device with the operating system lock and make a conscious decision about which backups you keep.",
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
          "Encrypchat includes standard, widely available cryptography: X25519 and ChaCha20-Poly1305 for messages and files, DTLS-SRTP for calls, and AES-256 with HMAC-SHA256 for local database encryption (SQLCipher, which links OpenSSL). You are responsible for complying with the cryptography import, use, and export rules that apply in your jurisdiction.",
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
          "Pending from the operator: legal entity, governing law, competent forum, and contact channel. Until then, no general contact address is published. For reporting a security bug there is one, in the privacy policy.",
        ],
      },
    ],
  },
  security: {
    metaTitle: "Security and threat model",
    metaDescription:
      "What Encrypchat protects against and what it does not: adversaries, metadata, the list of open limitations, and how to report a vulnerability.",
    h1: "Security and threat model",
    updated: "Last reviewed: 12 August 2026 · product state: pre-beta (phase 10)",
    updatedIso: "2026-08-12",
    summary:
      "Encrypchat encrypts content on the sending device and has no server that stores it. This page says what that protects, what it does not, and who learns what. A privacy product that does not publish its limits is lying by omission, so the important part is the list of known limitations, and it is here in full.",
    disclaimer:
      "This is the web edition of the threat model kept alongside the code (docs/threat-model.md): it describes what the software actually does as of the date above, not what we would like it to do. The software is pre-1.0 and has not passed an independent external security audit. It is written so that a non-cryptographer can follow it and a cryptographer can check it against the code; if this page and the code disagree, the page is wrong and we want to hear about it.",
    sections: [
      {
        id: "resumen",
        title: "What Encrypchat is, in one page",
        blocks: [
          [
            "Every device is both a client and a node. No server holds chats, media, or keys.",
            "Identity is an X25519 key pair generated on the device. The token (\u201cec_\u201d plus 64 hex characters) is the SHA-256 hash of the public key. There is no signup, no phone number, no email, no account.",
            "Messages are encrypted on the sending device for the recipient's public key (ephemeral X25519 plus ChaCha20-Poly1305) and travel over a direct TCP connection between the two devices.",
            "If the other side is offline, the already-encrypted message can sit in a blind relay: a mailbox that holds an opaque blob with a time to live and deletes it once delivered, after one courtesy re-delivery or when that window expires.",
            "Calls are direct WebRTC with DTLS-SRTP.",
          ],
        ],
        links: [
          { path: "/features", label: "How it works" },
          { path: "/download", label: "Download the app" },
        ],
      },
      {
        id: "protegemos",
        title: "What we protect",
        blocks: [
          [
            "The identity private key: it lives in the operating system's secure store (Keystore, Keychain, libsecret, DPAPI). It never leaves the device, never travels over the network, and never appears in logs.",
            "Message content: encrypted on the sending device. Neither the relay nor the network sees the text.",
            "Files and photos: encrypted at the source for sending, and sealed with authenticated encryption on disk.",
            "Audio and video: DTLS-SRTP between the two devices, with no media server of ours or anyone else's.",
            "Message bodies at rest: the database file is encrypted with SQLCipher (AES-256) and, on top of that, each body is sealed with authenticated encryption. Both keys come from the OS secure store.",
            "Message authorship: the sender is bound to the content, by proof of possession in the P2P handshake (EH02) and by a sealed-sender envelope on the relay route (ECS1).",
          ],
        ],
      },
      {
        id: "red-local",
        title: "Someone on your network",
        blocks: [
          "They cannot read the content of messages, files, or calls: everything is encrypted before it leaves the device.",
          "They can see that two IP addresses exchange traffic, how much, and when; infer things from size above 512 bytes, which is where padding stops equalizing everything (a photo is not mistaken for a short message, but a short message is not distinguishable from an acknowledgement either); cut your connection; and, if the relay is configured without TLS, read your token and the recipient's in the clear — the app warns about that persistently while it is the case.",
          "What they can no longer do is impersonate you with your public key: the handshake requires proving possession of the private one, and the relay envelope binds the sender to the content. Nor do they learn identities by listening, neither from the handshake nor from the frames of an already open session.",
          "What they can do, and it is the residual of this section: open a connection to your port with a throwaway identity and, by completing the handshake, confirm which token is behind that IP address.",
        ],
      },
      {
        id: "relay-operador",
        title: "The relay operator",
        blocks: [
          "The relay is optional and only steps in when the recipient is offline. It holds the recipient's token, an encrypted blob, and an expiry date.",
          "It cannot read the content: it has no key that would allow it, and the design does not contemplate giving it one. Nor can it recover your identity from the token, which is a hash.",
          "It can know that someone deposited a message for \u201cec_abc\u2026\u201d, of what size and at what time; see the IP address of whoever deposits and whoever collects, and therefore correlate \u201cthis IP writes to this token\u201d with \u201cthis IP owns this token\u201d; keep blobs longer than it promises or log that correlation, with no way for you to verify it from outside; and refuse to deliver.",
          "Do not trust the relay for anonymity. A blind relay protects the content, not the relationship. If your adversary includes whoever runs the infrastructure, use direct connections only, or put Tor or a VPN underneath.",
        ],
        links: [{ path: "/privacy", hash: "relay", label: "Privacy: blind relay" }],
      },
      {
        id: "acceso-fisico",
        title: "Someone with physical access to the device",
        blocks: [
          "Locked, with a passcode or biometrics: the main defense is the operating system's encryption, not ours.",
          "Unlocked: Encrypchat does not protect you. Whoever has the session open reads everything you read. There is no app PIN, no idle lock, and no hidden chats.",
          "Powered off, or on an unencrypted disk: the database file is encrypted with SQLCipher under a key derived from the one in the secure store, so a stolen laptop, a powered-off phone, or a recovered backup reveals neither who you talk to, nor your contacts, nor the dates, nor your attachment paths. What does stay visible is the media directory listing: each file's contents are sealed, but how many there are, their sizes, and their dates are filesystem metadata. Encrypting the device's disk is still a good idea.",
          "On uninstalling: on iOS, Linux, and Windows the private key survives uninstalling the app, because it lives in the system store and those platforms do not clear it. Only on Android does it disappear with the app. To leave completely there is identity deletion inside the app, which removes the key from the keyring and then the database and the attachments; if it is interrupted, it resumes on the next launch before anything else opens. What that deletion cannot do is overwrite the bytes: they remain as ciphertext without a key, not as blank space, and a system backup taken before the deletion may still hold the key.",
        ],
      },
      {
        id: "sistema-operativo",
        title: "Your operating system vendor",
        blocks: [
          "Apple, Google, Microsoft, and your Linux distribution sit below Encrypchat: they control the keyboard you type on, the screen that displays, the store where the key lives, and the storefront you downloaded the app from.",
          "We cannot protect you from them and we are not going to claim otherwise. What we do: send nothing to their services that is not needed, use no push notifications — there are none, precisely for this reason — and ship no analytics, no third-party SDKs, and no crash reporting that carries content.",
          "One explicit exception: calls use Google's public STUN servers to discover your public IP address.",
        ],
      },
      {
        id: "estado",
        title: "A state-resourced attacker",
        blocks: [
          "They cannot, as far as we know today, break X25519 or ChaCha20-Poly1305, or read content captured off the network.",
          "They can watch traffic at national scale and correlate who talks to whom from timing and sizes without reading anything; compromise a device with an operating-system exploit, and at that point everything is over; intercept or pressure whoever runs a relay; and block access.",
          "Encrypchat is not an anonymity tool and not a censorship-resistance tool. It protects the content and removes the central content server; it does not hide that you use it or who you use it with.",
        ],
      },
      {
        id: "otro-lado",
        title: "The person on the other side",
        blocks: [
          "The most frequent adversary in real life is someone you have already talked to.",
          "They cannot read your conversations with other people.",
          "They can save, screenshot, and forward everything you send them: encryption does not prevent a screen capture or a photo taken with another phone. They can create a new identity in seconds if you block them, because tokens cost nothing and there is no central directory. They have your public key, because they have you saved, but that no longer lets them present themselves as you to anyone.",
          "Blocking cuts off messages, photos, and calls from that token in two layers: the app discards the packet before decrypting it, and the core refuses to open or keep a session. It is applied against the sender's authenticated identity, not against a field the sender picks, so it cannot be evaded by impersonating another contact. Nor can it be evaded by rewriting the same key differently: a public key has one valid encoding and the others are rejected at the door. If a call with that token is in progress, it is ended before the block is applied. They are not told, and it does not stop them coming back with another identity.",
          "Blocking is local and one-sided: this device stops accepting, but the other party can keep depositing into a relay mailbox that nobody drains any more, until it expires.",
          "A stranger — someone who has your token but is not in your contacts — does not land in your chats: they land in a bounded requests inbox, text only, with no sound and with no way to leave files on your disk. Accepting them is an explicit act on your part.",
        ],
      },
      {
        id: "fuera-de-alcance",
        title: "Out of scope, by design",
        blocks: [
          "These are not pending bugs: they are things Encrypchat does not try to do.",
          [
            "Network anonymity. Your IP address is visible to your peer and to the relay. No onion routing, no mixnet.",
            "Hiding that you use Encrypchat. The protocol is neither obfuscated nor disguised as other traffic.",
            "Protecting you from your own device. Malware, malicious keyboards, or someone reading over your shoulder are out of scope.",
            "Preventing screenshots on the other side. No end-to-end encrypted system can.",
            "Content moderation. No server can read anything. The abuse report produces a local report that you decide what to do with; nobody receives it automatically.",
            "Account recovery. If you lose the private key, you lose the identity. Having a reset would mean somebody else can take it.",
            "Multi-device sync. One identity lives on one device; history is not synchronized.",
            "Per-message forward secrecy. There is no ratchet, and the nuance depends on the route the message takes: see the detail below.",
            "Network metadata. We do not claim \u201czero metadata\u201d and we will not while there is a network involved.",
          ],
          "On forward secrecy, the full nuance: a P2P session does have per-session forward secrecy, because the transport key comes from an exchange between the two ephemeral handshake keys, which are destroyed when the handshake ends — whoever recorded the traffic and later obtains both identity keys cannot decrypt that conversation. What there is no granularity for is the individual message: whoever obtains a session key, by pulling it out of a device's memory while the session is alive, reads that whole session. On the relay route there is no forward secrecy at all: the blob is closed against your static key, so whoever obtains your private key and has stored blobs reads them.",
        ],
      },
      {
        id: "metadatos",
        title: "Metadata: who learns what",
        blocks: [
          [
            "A network observer (your Wi-Fi, your ISP) learns that your IP talks to another IP, the volume, the timing, the size of each message above 512 bytes, and that this is Encrypchat traffic, from the first bytes of the handshake. It does not learn the content, nor identities — neither from the handshake nor from the frames of an established session, which are encrypted end to end of the socket — nor the difference between an acknowledgement and a short message, nor the tokens on the relay route if that relay uses TLS.",
            "The relay operator learns the recipient's token, the blob size, the deposit and collection times, and the IP address of both ends. It does not learn the content, the sender's token, or file names.",
            "Google's public STUN learns your public IP address and the moment you start or receive a call. It does not learn who you talk to, what you say, or your token.",
            "Your peer learns your token, your public key, your IP address for the duration of the connection, and everything you send them. They do not learn your other conversations.",
            "Whoever holds your unlocked device learns everything.",
            "Encrypchat — that is, us — learns nothing from the app: we operate no content servers and there is no telemetry or analytics. The one exception is not in the app but on this website, which is served by Cloudflare and records standard access logs — IP address, user agent, and timestamp — like any hosting provider.",
          ],
          "Three honest notes on that list. The relay sees the recipient's token: that is unavoidable, because without it there is no mailbox to leave the blob in, which is why it is optional and why we always prefer a direct connection. Google's STUN sees your IP when you call: it is a third party we do not control, and it is there because without it calls do not traverse most home NATs — if that does not work for you, do not use calls. And correlation is the realistic attack: nobody is going to break ChaCha20, they are going to look at who talked to whom and when.",
        ],
        links: [{ path: "/privacy", hash: "terceros", label: "Privacy: third parties involved" }],
      },
      {
        id: "identidad",
        title: "Identity and token",
        blocks: [
          "An X25519 key pair from the system's cryptographic random generator. The token is \u201cec_\u201d plus the SHA-256 hash of the public key in hex. The private key lives in the OS secure store. The contact card you share includes your public key in the clear: it is public by design, because whoever writes to you needs it.",
          "The token does not authenticate anything on its own: it is an identifier, not a credential. A token that arrives over a channel someone controls may well be that someone's token. Verify it over a separate channel.",
          "One key, one token. For the token to be a stable name for a key pair, each key must have exactly one encoding, and X25519 does not give that for free: the curve ignores the high bit and reduces modulo p, so several 32-byte strings are the same key for a Diffie-Hellman exchange and different keys for a hash. Every public key that comes in — contact card, QR, wire, core boundary — is rejected unless it arrives in its reduced form. Without that check, a blocked peer came back with the same key written differently and a clean token.",
          "Missing: comparable safety numbers inside the app, and a warning when a contact's key changes.",
        ],
      },
      {
        id: "canal-p2p",
        title: "The P2P channel and the EH02 handshake",
        blocks: [
          "Direct TCP with length-prefixed frames. On connect, EH02 runs: four messages with mutual authentication. The caller sends a magic value, a version, and a nonce, with no identity; the listener replies with a single-use ephemeral key and another nonce, also with no identity; the caller proves its identity by sealing it against that ephemeral key; and the listener, now knowing who it is talking to, proves its own by sealing it against the caller's key.",
          "Both proofs use the same double Diffie-Hellman primitive as the relay blobs: opening them requires an exchange only the verifier can compute, and that cannot be done with the victim's public key. Each proof is bound, via authenticated data, to the version, the role, both nonces, and the session's ephemeral key, so it is useless on another connection or in the opposite direction. Limits: a 5-second handshake, 32 unauthenticated connections at a time, and a 4 KiB pre-authentication buffer.",
          "This replaces EH01, whose proof could be constructed from the verifier's public key and therefore proved nothing. Both ends have to be updated together, and an older core refuses to start rather than degrade.",
          "What it achieves for identity exposure: the listener emits nothing identifiable until it has verified the caller. A passive network observer learns no identity from the handshake, and whoever opens a TCP connection without being able to prove any identity gets nothing. A blocked peer is rejected between the third and fourth messages, so it does not get to learn who answered either.",
          "What it does not achieve: the caller has to identify itself first. There is no way to prove anything to someone whose key you do not know yet, so an attacker who generates a throwaway identity and completes the handshake does obtain the listener's identity. Closing that fully would require the caller to know the other side's public key in advance; today a dial is addressed by token, and the token is a hash the key cannot be recovered from.",
          "Session key and encrypted transport: each end contributes a single-use ephemeral key, and from those comes the session key that encrypts all of the transport, header included. The header used to travel in the clear with only the payload encrypted end to end, so anyone sniffing the Wi-Fi read the sender token of every frame and could draw the social graph without decrypting anything. Now an observer sees a length prefix and opaque bytes.",
          "There is one key per direction, and the nonce is an implicit counter that never travels: the receiver only tries the next one. A frame that is replayed, reordered, dropped, or injected inside a session does not decrypt, and the session is closed. Within a session the flow is exactly-once and in order, or it is cut.",
          "What remains visible is size. Anything that fits in 512 bytes of plaintext goes out at the same size — an acknowledgement, an \u201cok\u201d, and a short paragraph are indistinguishable — but above that the length is the message's, and a photo is distinguishable from text. More padding does not pay off: it hides neither volume nor timing, and the observer already knows which IP talks to which IP, which is the expensive fact. We declare it as a limit rather than dress it up. It is also visible that the traffic is Encrypchat's: the first handshake message starts with \u201cEH02\u201d.",
        ],
      },
      {
        id: "relay-ciego",
        title: "Blind relay and proof of possession",
        blocks: [
          "Three operations: deposit, request a challenge, and collect. Collecting requires a proof of possession: the relay generates an ephemeral key pair and a nonce, and hands over the mailbox only to whoever demonstrates via a Diffie-Hellman exchange that they own the token. The challenge is single-use, expires in 2 minutes, and carries no recipient, so asking for one says nothing about which mailbox anyone is pointing at; it is identified by an opaque id, so a third party cannot step on someone else's challenge and leave their mailbox undrained. It is consumed only if the proof verifies.",
          "Blobs have a time to live: 24 hours by default, 7 days maximum. They are not deleted on delivery: they stay leased for 60 seconds, hidden even from their recipient, and are delivered a second and final time if the client comes back afterwards. That way a client the operating system kills between the relay's response and its own save does not lose the message. There is a per-mailbox quota (8 MiB), a global disk ceiling, and a per-IP limit. The logs do not record the destination token.",
          "The envelope binds the sender to the content: the key that opens the body is derived from the sender's permanent key against yours, so producing a blob that opens correctly requires holding that private key, and there is no separate sender field that could be swapped out. That check has a deliberate property: only you can verify it. The proof is not transferable to a third party — anyone with your private key could have fabricated the same blob — and that is on purpose, because a public signature would turn every message into a receipt of who wrote to you. It serves to attribute and to block; it does not serve as evidence to anyone else.",
          "Two clarifications so that is not read as more than it is. The deniability is cryptographic and it is against the blob: it is not against your testimony backed by circumstantial evidence, and the timestamps, the IP addresses, and the correlation at the relay all still exist. And it is deniability towards third parties, not towards the recipient: for them the attribution is strong, which is exactly what makes blocking work.",
          "What it does not give: deposits are not authenticated, and TLS is the responsibility of whoever runs the relay. Delivery is at least once, at most twice: if the client dies on both attempts the message is lost anyway, and the price of the two attempts is that every blob crosses the network twice — the client discards the duplicate by message id.",
        ],
      },
      {
        id: "llamadas",
        title: "Calls",
        blocks: [
          "Signaling travels only over the P2P channel, encrypted like any other message, never over the relay. The media goes point to point with DTLS-SRTP. There is no SFU, no TURN, and no media server: audio and video never pass through infrastructure of ours. Without TURN, some NAT combinations do not connect; we prefer the call to fail over standing up a server your voice passes through.",
          "The microphone and camera are requested when you accept, not when it rings. An invitation from a token that is not in your contacts is dropped without ringing.",
        ],
        links: [{ path: "/privacy", hash: "llamadas", label: "Privacy: calls" }],
      },
      {
        id: "almacenamiento",
        title: "Local storage",
        blocks: [
          "SQLite in the app's private directory, encrypted as a file with SQLCipher under a key derived from the one in the secure store — derived, not the same one, so the same bytes are not reused across two primitives. On top of that, message bodies and files are sealed with ChaCha20-Poly1305: they are two distinct layers, and the inner one keeps protecting if the database is ever opened. On Android, the system's automatic backup is disabled for the app.",
          "What file encryption does not cover: an unlocked device with the keyring accessible — whoever reads the key opens the database, and there the boundary is the system lock screen — and the media directory listing, whose contents are sealed but whose file count, sizes, and dates are filesystem metadata.",
          "If the keyring loses the key, the history is lost: the app says so on screen instead of starting a fresh database on top.",
          "Disk is not infinite and it is the other side that fills it, so incoming attachments have a ceiling: 512 MiB per peer and 2 GiB in total, checked before the file is written. Past the ceiling the attachment is rejected and the app tells you, instead of growing until the system complains. A stranger does not even reach that budget: the requests inbox accepts no files.",
        ],
      },
      {
        id: "frontera-ffi",
        title: "The boundary between core and interface",
        blocks: [
          "Cryptography, identity, and the P2P node are in Rust; the interface is in Flutter. Every symbol on the boundary has a written contract: which pointers must be valid, who frees what, what is written on error (nothing), and how long each call blocks. The entry points catch panics and turn them into error codes.",
          "Sensitive material that crosses: the identity key and the database key. Rust wipes its copies and the Dart bridge wipes its own: every native buffer that held a key or a plaintext is zeroed before being freed, including the ones the core itself allocates. One residue remains that the language does not allow closing: the copy that lives on the Dart heap — the identity key while a session is open, and the base64 string the secure store returns when loading it — is managed by the garbage collector, which may have moved or duplicated it. Closing that would mean the key does not cross the boundary on every message, and instead decryption happens inside the core with the copy the node already holds; that is a change to the boundary's surface, not to the client.",
          "Node calls with a blocking budget — send, 15 seconds; mark, 10 — run on a separate thread, so a peer that accepts the connection and then says nothing does not freeze the interface.",
        ],
      },
      {
        id: "limitaciones",
        title: "Known limitations today",
        blocks: [
          "The actual state of the code as of the date above. It is updated when that changes, not when it suits us.",
          {
            ordered: [
              "Authorship comes from the transport and the envelope, not from the encryption itself. The P2P handshake does prove possession of the private key and relay blobs do bind the sender: the two impersonations that earlier versions of this document described as open are closed, in the core and in the client that has to call it. What remains true is that the encryption operation on its own does not say who wrote — anyone with your public key can produce something that decrypts correctly — so every new route added has to authenticate explicitly by one of the two paths: the crypto layer does not do it by itself. And the attribution you get is good for you, not before a third party.",
              "A requeued relay blob is no longer shown twice, but it can still arrive late. The client remembers the ids of the envelopes it has opened and discards the repeat; the table is pruned with the freshness window itself, so it does not grow without bound. What that id does not say is when the message belonged: an authentic envelope captured and deposited later, within the 7-day window, is new to a device that never saw it and will be shown with its original date. That is why call signaling still does not go over the relay: a ring is not annoying for being repeated, it is annoying for arriving at 4 in the morning.",
              "Blocking does not stop someone who uses a new identity. A block is always applied against an identity the sender does not choose — proven by the handshake on P2P, taken from the ciphertext on the relay route — and it ends an in-progress call before taking effect. What nobody can prevent is the same person generating another token and coming back.",
              "A stranger can write to you, within a ceiling. Whoever has your token lands in the requests inbox: text only, up to 5 messages of 4 KiB per sender and 20 senders at a time, with no notification and no attachments or calls. Anything beyond that is discarded before it touches the disk — and, if you are not a contact, before it is even decrypted — so the maximum cost of all strangers combined is 400 KiB of text plus the noise of having to look at the inbox. When the 20 slots are full, the oldest request is evicted to make room for the new one: it is a rolling window, not a queue that closes. The consequence is that twenty throwaway identities — which cost nothing — can push out a request you never got to read, although they cannot cut you off indefinitely. There is also no way to know whether the token reached them from who you think.",
              "Someone can fill your relay mailbox, and silently. Depositing does not require authentication — that is needed so anyone can write to you while you are offline — so whoever knows your token can occupy your quota and cause the messages sent to you meanwhile to be lost. The relay answers everyone the same way, accepted or discarded, and that opacity is deliberate: distinguishing the two turned the relay into an informant about your presence, and telling the honest sender is the same request as telling whoever is flooding you. The price is that neither of you finds out. Messages over a direct connection are unaffected, and the mailbox frees up as blobs expire.",
              "Attachment storage has a cap and it fills up. 512 MiB per contact and 2 GiB in total: a contact who insists will see their sends rejected instead of filling your disk, but the rejection is silent for them and visible to you as a quota warning. Deleting the conversation frees the space; there is no automatic purge by age.",
              "The media directory listing is visible, even though the contents are sealed and the database is encrypted: how many attachments you have, their sizes, and their dates.",
              "The private key survives uninstalling on iOS, Linux, and Windows: it lives in the system store and those platforms do not clear it. To leave completely, use the app's identity deletion, which does remove the key from the keyring; uninstalling on its own is not enough.",
              "The caller identifies itself first. When a P2P connection is opened, the party answering reveals nothing until it has verified the other side, but the other side does have to reveal itself first. That is a property of the handshake pattern, not an oversight: nothing can be proven to a key you do not know yet. Practical consequence: someone who generates a throwaway identity and completes the handshake confirms which token is behind that IP address.",
              "The relay's rate limit depends on the operator's configuration. The relay knows how to charge the limit to the real IP behind a reverse proxy, but only if the operator tells it which proxies to trust; without that list it ignores the header and charges the connecting address, which behind a proxy is a single one for everybody. There is a global disk ceiling — 1 GiB by default, which rejects rather than evicting anything already accepted. There is no defense against distributed flooding: a flood reads nobody else's messages, but it leaves the relay useless for new ones.",
              "The abuse report no longer leaves through the clipboard, but on mobile you do not choose where it lands. The default route is saving it as a text file, and on Linux and Windows the system dialog opens, so you pick the path. On iOS and Android there is no save dialog, so the file goes into a folder of the app's own: on iOS Documents/Informes, visible from the Files app, and on Android the app's folder on shared storage, which a computer plugged in by cable can read. That is the residual, and we are not hiding it: what deleting your identity does do is take that folder with it, so a report does not outlive the identity it names. Copying to the clipboard still exists as an explicit second action, underneath a sentence saying what the clipboard is: removing it left no way out for pasting the report into an email from a phone, and pushed towards something worse, like a screenshot. The report is generated locally and nobody receives it.",
              "A peer that opens a session can degrade the node. It is enough to complete the handshake with an identity of their own — which costs nothing — to make the device allocate memory for whatever that peer decides to send, and to make the interface spend time processing it before it can reject it. The limits that exist are set on message and unauthenticated-connection counts, not on bytes or work. This is an availability problem against your own device, not a confidentiality one: nobody reads anything this way. Pending before 1.0.",
              "No contact verification in the app: no safety numbers and no key-change warning.",
              "No screenshot protection on any platform.",
              "No per-message forward secrecy.",
            ],
          },
        ],
        links: [
          { path: "/privacy", hash: "limitaciones", label: "Privacy: what we do not promise" },
        ],
      },
      {
        id: "reportar",
        title: "Reporting a vulnerability",
        blocks: [
          "info@elnerd.com — a mailbox attended by the operator. It is an address on another domain, so it is confirmed from the product itself on this page, in the privacy policy, and at https://encrypchat.com/.well-known/security.txt; if you found it anywhere else, check it against one of those sources. There is no public key for encrypted reports yet; if you need one, ask for it in a first email without details.",
          "That those sources keep saying the same thing, and that the security.txt is not expired, does not depend on anyone remembering: an automated check runs on every build and fails a month before the expiry date, or as soon as one of the copies drifts. A security mailbox that stopped existing is worse than publishing none, because whoever finds the bug believes they reported it.",
          "We ask for coordinated disclosure: tell us what you found and leave us a reasonable window to fix it before publishing. We do not commit to response times and there is no bug bounty program. We do publish findings and their state alongside the code, including the ones we have not closed.",
          "This is the channel for security bugs in the software. It is not support, it is not the privacy mailbox, and it is not for reporting another user: the app's abuse report is local and nobody receives it.",
        ],
        links: [{ path: "/privacy", hash: "seguridad", label: "Privacy: reporting a bug" }],
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
