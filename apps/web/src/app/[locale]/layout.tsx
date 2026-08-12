import { Manrope } from "next/font/google";
import { notFound } from "next/navigation";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";
import { isLocale, locales, type Locale } from "@/i18n/config";

const manrope = Manrope({
  subsets: ["latin", "latin-ext"],
  variable: "--font-sans",
  weight: ["400", "600", "700"],
});

const manropeDisplay = Manrope({
  subsets: ["latin", "latin-ext"],
  variable: "--font-display",
  weight: ["700"],
});

export function generateStaticParams() {
  return locales.map((locale) => ({ locale }));
}

export default async function LocaleLayout({
  children,
  params,
}: Readonly<{
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}>) {
  const { locale: raw } = await params;
  if (!isLocale(raw)) notFound();
  const locale: Locale = raw;

  return (
    <html lang={locale}>
      <body className={`${manrope.variable} ${manropeDisplay.variable}`}>
        <div className="shell">
          <SiteHeader locale={locale} />
          <main>{children}</main>
          <SiteFooter locale={locale} />
        </div>
      </body>
    </html>
  );
}
