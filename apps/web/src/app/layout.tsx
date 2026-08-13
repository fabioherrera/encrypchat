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
  // Declaring `icons` suppresses the file convention, so every icon is listed here
  // and every file lives in `public/`. `favicon.ico` carries three frames: from
  // `app/` Next read only the first one and advertised `sizes="16x16"`, which made
  // browsers at 2x skip the .ico and downscale the 192 logo instead of using the
  // 32 px mark drawn for that size.
  icons: {
    icon: [
      { url: "/favicon.ico", type: "image/x-icon", sizes: "16x16 32x32 48x48" },
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
