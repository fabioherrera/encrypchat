import {
  CHECKSUMS_URL,
  PLATFORM_DOWNLOADS,
  PLATFORM_IDS,
  TEST_RELEASE_URL,
} from "@/lib/site";
import type { Dictionary } from "@/i18n/types";

type Labels = Dictionary["platforms"];

export function PlatformDownloadList({ labels }: { labels: Labels }) {
  return (
    <ul className="platformList">
      {PLATFORM_IDS.map((id) => {
        const files = PLATFORM_DOWNLOADS[id];
        return (
          <li key={id}>
            <span>{labels[id]}</span>
            <span className="platformActions">
              {files ? (
                files.map((file) => (
                  <a
                    key={file.kind}
                    className="btn btnSm"
                    href={file.href}
                    rel="noopener noreferrer"
                  >
                    {labels[file.kind]}
                  </a>
                ))
              ) : (
                <span className="muted">{labels.comingSoon}</span>
              )}
            </span>
          </li>
        );
      })}
    </ul>
  );
}

export function DownloadReleaseLinks({
  checksums,
  releasePage,
}: {
  checksums: string;
  releasePage: string;
}) {
  return (
    <p className="downloadExtras">
      <a href={CHECKSUMS_URL} rel="noopener noreferrer">
        {checksums}
      </a>
      <span aria-hidden="true"> · </span>
      <a href={TEST_RELEASE_URL} rel="noopener noreferrer">
        {releasePage}
      </a>
    </p>
  );
}
