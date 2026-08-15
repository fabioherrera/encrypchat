export const SITE_URL = "https://encrypchat.com";
export const SITE_NAME = "Encrypchat";
export const TAGLINE = "DECENTRALIZED P2P CHAT | ZERO-CLOUD";

// Security reports only. Also written out in `public/.well-known/security.txt` and in the
// privacy policy copy (`#seguridad`), which is where a researcher confirms it: the mailbox is
// on a different domain, so all three have to agree.
export const SECURITY_CONTACT = "info@elnerd.com";

// Data protection and rights requests, deliberately not the security mailbox: one is read by
// whoever fixes the bug, the other answers a legal deadline. `check-security-txt.sh` holds the
// policy copy against this value, because the way a published legal channel fails is silently.
export const PRIVACY_CONTACT = "privacy@encrypchat.com";

export const PLATFORM_IDS = [
  "android",
  "ios",
  "linux",
  "windows",
] as const;

export type PlatformId = (typeof PLATFORM_IDS)[number];

/** GitHub repo that holds the test installers. */
export const GITHUB_REPO = "https://github.com/fabioherrera/encrypchat";

/** Bump this when a new test batch replaces the previous one. Not a `v*` tag:
 *  that pattern starts the Windows CI workflow. */
export const TEST_RELEASE_TAG = "pruebas-2026-08-15-relay";

export const TEST_RELEASE_URL = `${GITHUB_REPO}/releases/tag/${TEST_RELEASE_TAG}`;

export type DownloadKind = "apk" | "rpm" | "tarball" | "setup" | "zip";

export type PlatformDownload = {
  href: string;
  kind: DownloadKind;
};

function releaseAsset(name: string): string {
  return `${GITHUB_REPO}/releases/download/${TEST_RELEASE_TAG}/${name}`;
}

/** What `/download` and the home platform list actually link to. `null` means
 *  there is no file yet — the UI says so instead of inventing a URL. */
export const PLATFORM_DOWNLOADS: Record<PlatformId, PlatformDownload[] | null> = {
  android: [
    {
      href: releaseAsset("encrypchat-android-arm64-1.0.7.apk"),
      kind: "apk",
    },
  ],
  linux: [
    {
      href: releaseAsset("encrypchat-1.0.7-1.fc44.x86_64.rpm"),
      kind: "rpm",
    },
    {
      href: releaseAsset("encrypchat-linux-x64-1.0.7.tar.gz"),
      kind: "tarball",
    },
  ],
  ios: null,
  windows: [
    {
      href: `${GITHUB_REPO}/releases/download/pruebas-2026-08-14-barra/encrypchat-windows-x64-1.0.6-setup.exe`,
      kind: "setup",
    },
    {
      href: `${GITHUB_REPO}/releases/download/pruebas-2026-08-14-barra/encrypchat-windows-x64-1.0.6.zip`,
      kind: "zip",
    },
  ],
};

export const CHECKSUMS_URL = releaseAsset("SHA256SUMS");
