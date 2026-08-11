import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Features",
  description:
    "P2P encrypted messaging, device-local storage, cryptographic tokens, and optional blind relays for Encrypchat.",
  alternates: { canonical: "/features" },
};

export default function FeaturesPage() {
  return (
    <article className="section prose">
      <h1>Features</h1>
      <p className="muted">
        Encrypchat is designed so readable chats never sit in our cloud.
      </p>

      <h2>End-to-end encryption</h2>
      <p>
        Messages are encrypted on your device for the recipient&apos;s key
        before they leave. Only the intended device can decrypt them.
      </p>

      <h2>Peer-to-peer first</h2>
      <p>
        When both sides are online, traffic prefers a direct device-to-device
        path. That cuts intermediaries for live chat, media, and calls.
      </p>

      <h2>Zero-cloud content</h2>
      <p>
        Chat history and media are stored locally on your phone or computer.
        We do not operate a message inbox that can read your conversations.
      </p>

      <h2>Blind relay (optional, offline)</h2>
      <p>
        If the recipient is offline, a relay may temporarily hold{" "}
        <em>ciphertext</em> addressed to their token, then delete it after
        delivery. Relays are not a cloud backup of your chat history and cannot
        decrypt contents.
      </p>

      <h2>Token identity</h2>
      <p>
        Contacts are cryptographic tokens (from public keys), exchanged via QR
        or paste. There is no central phone-number directory as the source of
        truth.
      </p>

      <p>
        <Link className="btn" href="/download">
          Get Encrypchat
        </Link>
      </p>
    </article>
  );
}
