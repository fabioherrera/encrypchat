export const SITE_URL = "https://encrypchat.com";
export const SITE_NAME = "Encrypchat";
export const TAGLINE = "DECENTRALIZED P2P CHAT | ZERO-CLOUD";

// Security reports only. Also written out in `public/.well-known/security.txt` and in the
// privacy policy copy (`#seguridad`), which is where a researcher confirms it: the mailbox is
// on a different domain, so all three have to agree.
export const SECURITY_CONTACT = "info@elnerd.com";

export const PLATFORM_IDS = [
  "android",
  "ios",
  "linux",
  "windows",
] as const;

export type PlatformId = (typeof PLATFORM_IDS)[number];
