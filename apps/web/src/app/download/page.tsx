import type { Metadata } from "next";
import { PLATFORMS } from "@/lib/site";

export const metadata: Metadata = {
  title: "Download",
  description:
    "Download Encrypchat for Android, iOS, Linux (Fedora), and Windows. Builds are coming soon — join the waitlist via the site.",
  alternates: { canonical: "/download" },
};

export default function DownloadPage() {
  return (
    <article className="section prose">
      <h1>Download</h1>
      <p className="muted">
        Native apps for every first-class platform. Installers will appear here
        as Phase 8 packaging lands.
      </p>
      <ul className="platformList">
        {PLATFORMS.map((p) => (
          <li key={p.id}>
            <span>{p.name}</span>
            <span className="muted">{p.status}</span>
          </li>
        ))}
      </ul>
      <p>
        Prefer building from source while binaries are pending? See the project
        roadmap in the public repository documentation.
      </p>
    </article>
  );
}
