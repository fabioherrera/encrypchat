import type { Metadata } from "next";
import { SITE_NAME, SITE_URL, TAGLINE } from "@/lib/site";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  applicationName: SITE_NAME,
  authors: [{ name: SITE_NAME, url: SITE_URL }],
  robots: {
    index: true,
    follow: true,
  },
  // Next emits `favicon.ico` from the file convention on its own, but declaring
  // `icons` here suppresses that convention for `apple-icon.png`, so the Apple
  // touch icon has to be listed or iOS falls back to a screenshot.
  icons: {
    icon: [
      { url: "/icon-192.png", type: "image/png", sizes: "192x192" },
      { url: "/icon-512.png", type: "image/png", sizes: "512x512" },
    ],
    apple: [{ url: "/apple-icon.png", sizes: "180x180", type: "image/png" }],
  },
  openGraph: {
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: `${SITE_NAME} logo — ${TAGLINE}`,
      },
    ],
  },
};

/** Passthrough root so `[locale]/layout` owns `<html lang>`. */
export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return children;
}
