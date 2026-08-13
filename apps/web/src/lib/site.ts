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

/** GitHub repo that holds the test installers. */
export const GITHUB_REPO = "https://github.com/fabioherrera/encrypchat";

/** Bump this when a new test batch replaces the previous one. Not a `v*` tag:
 *  that pattern starts the Windows CI workflow. */
export const TEST_RELEASE_TAG = "pruebas-2026-08-13-ventana";

export const TEST_RELEASE_URL = `${GITHUB_REPO}/releases/tag/${TEST_RELEASE_TAG}`;

export type DownloadKind = "apk" | "rpm" | "tarball";

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
      href: releaseAsset("encrypchat-android-arm64-1.0.2.apk"),
      kind: "apk",
    },
  ],
  linux: [
    {
      href: releaseAsset("encrypchat-1.0.2-1.fc44.x86_64.rpm"),
      kind: "rpm",
    },
    {
      href: releaseAsset("encrypchat-linux-x64-1.0.2.tar.gz"),
      kind: "tarball",
    },
  ],
  ios: null,
  windows: null,
};

export const CHECKSUMS_URL = releaseAsset("SHA256SUMS");
