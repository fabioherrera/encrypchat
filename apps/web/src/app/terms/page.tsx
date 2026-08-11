import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Terms",
  description:
    "Encrypchat terms of use stub: software provided as-is during development; no guarantee of uninterrupted delivery.",
  alternates: { canonical: "/terms" },
};

export default function TermsPage() {
  return (
    <article className="section prose">
      <h1>Terms of use</h1>
      <p className="muted">Stub terms — finalize with counsel before store launch (Phase 9).</p>

      <h2>Service</h2>
      <p>
        Encrypchat provides client software for encrypted peer-to-peer
        messaging. Optional infrastructure (such as blind relays or STUN/TURN)
        may assist connectivity without providing a readable message archive.
      </p>

      <h2>No absolute security promise</h2>
      <p>
        Encryption reduces risk; it does not make compromise impossible.
        Endpoint security, physical access, malware, and network metadata remain
        real threats.
      </p>

      <h2>Availability</h2>
      <p>
        During development, features and binaries may be incomplete. Relays and
        discovery helpers may be unavailable or rate-limited.
      </p>

      <h2>Acceptable use</h2>
      <p>
        Do not use Encrypchat to violate applicable law. We may refuse abusive
        use of any infrastructure we operate.
      </p>
    </article>
  );
}
