import Image from "next/image";
import Link from "next/link";
import { JsonLd } from "@/components/JsonLd";
import { LiveChatPhone } from "@/components/LiveChatPhone";
import { PLATFORMS, SITE_NAME, SITE_URL } from "@/lib/site";

const softwareLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: SITE_NAME,
  applicationCategory: "CommunicationApplication",
  operatingSystem: "Android, iOS, Linux, Windows",
  url: SITE_URL,
  description:
    "Peer-to-peer encrypted messenger. Messages stay on your devices; optional blind relays hold ciphertext only.",
  offers: {
    "@type": "Offer",
    price: "0",
    priceCurrency: "USD",
  },
};

const orgLd = {
  "@context": "https://schema.org",
  "@type": "Organization",
  name: SITE_NAME,
  url: SITE_URL,
  logo: `${SITE_URL}/logo-transparent.png`,
};

export default function HomePage() {
  return (
    <>
      <JsonLd data={softwareLd} />
      <JsonLd data={orgLd} />

      <section className="heroBleed" aria-label="Hero">
        <div className="heroInner">
          <div className="heroCopy">
            <h1 className="heroLogo">
              <Image
                src="/logo-mark.png"
                alt=""
                width={160}
                height={172}
                className="heroMark"
                priority
              />
              <span className="heroWordmark">{SITE_NAME}</span>
              <span className="heroTagline">
                DECENTRALIZED P2P CHAT | ZERO-CLOUD
              </span>
            </h1>
            <p className="heroLead">
              Peer-to-peer encrypted chat on your device — not a cloud inbox we
              can read.
            </p>
            <div className="heroActions">
              <Link className="btn" href="/download">
                Download
              </Link>
              <Link className="btnGhost" href="/features">
                How it works
              </Link>
            </div>
          </div>
          <div className="heroVisual">
            <LiveChatPhone />
          </div>
        </div>
      </section>

      <section className="section">
        <h2>Built for device-local privacy</h2>
        <p className="muted prose">
          Each install is a client and a local node. Identity is a cryptographic
          token you share (QR or paste) — not a phone-number directory we
          control. When someone is offline, an optional <strong>blind relay</strong>{" "}
          can hold sealed ciphertext until they reconnect; relays cannot read
          message contents.
        </p>
        <p className="muted prose" style={{ marginTop: "0.75rem" }}>
          In the app you will see <strong>P2P</strong> when peers connect
          directly, <strong>relay</strong> when sealed ciphertext waits offline,
          and offline when the device cannot reach the network.
        </p>
      </section>

      <section className="section">
        <h2>Platforms</h2>
        <ul className="platformList">
          {PLATFORMS.map((p) => (
            <li key={p.id}>
              <span>{p.name}</span>
              <span className="muted">{p.status}</span>
            </li>
          ))}
        </ul>
      </section>
    </>
  );
}
