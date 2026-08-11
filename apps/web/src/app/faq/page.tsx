import type { Metadata } from "next";
import { JsonLd } from "@/components/JsonLd";
import { SITE_NAME, SITE_URL } from "@/lib/site";

export const metadata: Metadata = {
  title: "FAQ",
  description:
    "Frequently asked questions about Encrypchat: P2P encryption, zero-cloud storage, blind relays, and platforms.",
  alternates: { canonical: "/faq" },
};

const faqs = [
  {
    q: "Is Encrypchat end-to-end encrypted?",
    a: "Yes. Messages are encrypted on the sender device for the recipient’s key. Readable plaintext is meant to exist only on the endpoints.",
  },
  {
    q: "Do you store my chats in the cloud?",
    a: "No. Chat content is stored on your devices. That is what we mean by zero-cloud content.",
  },
  {
    q: "What is a blind relay?",
    a: "An optional helper for offline delivery. It can hold sealed ciphertext for your token until you come online, then delete it. It cannot decrypt message contents.",
  },
  {
    q: "Which platforms are supported?",
    a: "Android, iOS, Linux (Fedora), and Windows are first-class targets. Download links appear when installers are ready.",
  },
  {
    q: "How do I add a contact?",
    a: "You exchange cryptographic tokens (for example via QR). There is no central phone-number directory as the source of truth.",
  },
];

const faqLd = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  mainEntity: faqs.map((f) => ({
    "@type": "Question",
    name: f.q,
    acceptedAnswer: {
      "@type": "Answer",
      text: f.a,
    },
  })),
  url: `${SITE_URL}/faq`,
  isPartOf: { "@type": "WebSite", name: SITE_NAME, url: SITE_URL },
};

export default function FaqPage() {
  return (
    <article className="section prose">
      <JsonLd data={faqLd} />
      <h1>FAQ</h1>
      <dl className="faq">
        {faqs.map((f) => (
          <div key={f.q}>
            <dt>{f.q}</dt>
            <dd>{f.a}</dd>
          </div>
        ))}
      </dl>
    </article>
  );
}
