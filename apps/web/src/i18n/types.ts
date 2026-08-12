export type FaqItem = { q: string; a: string };

/** A paragraph (string) or an unordered list (string[]). */
export type LegalBlock = string | string[];

export type LegalSection = {
  /** Stable anchor, identical across locales. */
  id: string;
  title: string;
  blocks: LegalBlock[];
};

export type LegalDoc = {
  metaTitle: string;
  metaDescription: string;
  h1: string;
  updated: string;
  /** ISO date used for dateModified in JSON-LD. */
  updatedIso: string;
  summary: string;
  disclaimer: string;
  sections: LegalSection[];
};

export type Dictionary = {
  meta: {
    titleDefault: string;
    titleTemplate: string;
    description: string;
    keywords: string[];
    ogLocale: string;
  };
  nav: {
    features: string;
    download: string;
    faq: string;
    cta: string;
    primaryAria: string;
    langSwitcherAria: string;
  };
  footer: {
    note: string;
    privacy: string;
    terms: string;
    faq: string;
    download: string;
    aria: string;
  };
  platforms: {
    android: string;
    ios: string;
    linux: string;
    windows: string;
    comingSoon: string;
  };
  home: {
    heroAria: string;
    lead: string;
    ctaDownload: string;
    ctaFeatures: string;
    privacyTitle: string;
    privacyP1: string;
    privacyP2Before: string;
    privacyP2P2p: string;
    privacyP2Mid: string;
    privacyP2Relay: string;
    privacyP2After: string;
    platformsTitle: string;
    softwareDescription: string;
  };
  features: {
    metaTitle: string;
    metaDescription: string;
    h1: string;
    intro: string;
    e2eeTitle: string;
    e2eeBody: string;
    p2pTitle: string;
    p2pBody: string;
    zeroCloudTitle: string;
    zeroCloudBody: string;
    relayTitle: string;
    relayBodyBefore: string;
    relayCiphertext: string;
    relayBodyAfter: string;
    tokenTitle: string;
    tokenBody: string;
    cta: string;
  };
  download: {
    metaTitle: string;
    metaDescription: string;
    h1: string;
    intro: string;
    sourceNote: string;
  };
  faq: {
    metaTitle: string;
    metaDescription: string;
    h1: string;
    items: FaqItem[];
  };
  legal: {
    relatedAria: string;
  };
  privacy: LegalDoc;
  terms: LegalDoc;
  redirect: {
    message: string;
    link: string;
  };
  demo: {
    peerName: string;
    diegoName: string;
    anaName: string;
    chatsLabel: string;
    statusOnline: string;
    dayToday: string;
    e2eeBanner: string;
    draftText: string;
    videoCallHint: string;
    videoCallBadge: string;
    videoCallYou: string;
    yesterday: string;
    mondayShort: string;
    m1: string;
    m2: string;
    m3Caption: string;
    m3Alt: string;
    m4Caption: string;
    m4Alt: string;
    m5Caption: string;
    m5Alt: string;
    m6: string;
    callLabel: string;
    callDetail: string;
    s1: string;
    s2: string;
    s3Caption: string;
    diegoPreview: string;
    anaPreview: string;
  };
};
