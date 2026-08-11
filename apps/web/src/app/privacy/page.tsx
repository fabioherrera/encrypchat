import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Privacy",
  description:
    "Encrypchat privacy overview: device-local chats, E2EE, and optional blind relays that only see ciphertext.",
  alternates: { canonical: "/privacy" },
};

export default function PrivacyPage() {
  return (
    <article className="section prose">
      <h1>Privacy</h1>
      <p className="muted">Stub policy — finalize with counsel before store launch (Phase 9).</p>

      <h2>What we want to collect</h2>
      <p>
        Encrypchat is designed so message content stays on your devices. We do
        not operate a cloud mailbox of readable chats.
      </p>

      <h2>On your device</h2>
      <p>
        Identity keys, contacts, and message history are stored locally. Protect
        your device with OS lock screens and backups you trust.
      </p>

      <h2>Blind relays</h2>
      <p>
        If you use a relay for offline delivery, that service may process
        ciphertext addressed to your token, delivery metadata necessary to route
        the blob, and TTL timers. Relays are not intended to decrypt content.
      </p>

      <h2>This website</h2>
      <p>
        encrypchat.com may use standard hosting logs (IP, user agent) via the
        CDN/host. We will disclose any analytics cookies before enabling them.
      </p>

      <h2>Contact</h2>
      <p>Privacy requests: privacy@encrypchat.com (mailbox to be activated).</p>
    </article>
  );
}
