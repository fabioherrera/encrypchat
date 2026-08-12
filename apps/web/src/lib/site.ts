export const SITE_URL = "https://encrypchat.com";
export const SITE_NAME = "Encrypchat";
export const TAGLINE = "DECENTRALIZED P2P CHAT | ZERO-CLOUD";

export const PLATFORM_IDS = [
  "android",
  "ios",
  "linux",
  "windows",
] as const;

export type PlatformId = (typeof PLATFORM_IDS)[number];
