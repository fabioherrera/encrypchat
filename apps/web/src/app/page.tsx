import type { Metadata } from "next";
import Link from "next/link";
import { SITE_NAME, SITE_URL } from "@/lib/site";
import { RootRedirect } from "@/components/RootRedirect";

export const metadata: Metadata = {
  title: SITE_NAME,
  description:
    "Encrypchat is a peer-to-peer encrypted messenger. Redirecting to the English site.",
  robots: { index: false, follow: true },
  alternates: {
    canonical: `${SITE_URL}/en`,
    languages: {
      en: `${SITE_URL}/en`,
      es: `${SITE_URL}/es`,
      "x-default": `${SITE_URL}/en`,
    },
  },
};

/** Static-export friendly entry: meta refresh + client replace to `/en`. */
export default function RootPage() {
  return (
    <html lang="en">
      <head>
        <meta httpEquiv="refresh" content="0;url=/en" />
        <link rel="canonical" href={`${SITE_URL}/en`} />
      </head>
      <body
        style={{
          margin: 0,
          fontFamily: "system-ui, sans-serif",
          background: "#F4F6F8",
          color: "#0F2744",
          display: "grid",
          minHeight: "100vh",
          placeItems: "center",
          padding: "1.5rem",
        }}
      >
        <RootRedirect />
        <p>
          <Link href="/en" style={{ color: "#0F2744", fontWeight: 600 }}>
            Encrypchat — continue
          </Link>
        </p>
      </body>
    </html>
  );
}
