import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";
import { JsonLd } from "@/components/JsonLd";
import { LiveChatPhone } from "@/components/LiveChatPhone";
import { isLocale, type Locale } from "@/i18n/config";
import { getDictionary } from "@/i18n/getDictionary";
import { localizedHref } from "@/i18n/path";
import { buildPageMetadata } from "@/lib/seo";
import { PLATFORM_IDS, SITE_NAME, SITE_URL, TAGLINE } from "@/lib/site";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale: raw } = await params;
  if (!isLocale(raw)) return {};
  return buildPageMetadata({ locale: raw, path: "" });
}

export default async function HomePage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale: raw } = await params;
  if (!isLocale(raw)) notFound();
  const locale: Locale = raw;
  const dict = getDictionary(locale);
  const t = dict.home;
  const platforms = dict.platforms;

  const softwareLd = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: SITE_NAME,
    applicationCategory: "CommunicationApplication",
    operatingSystem: "Android, iOS, Linux, Windows",
    url: `${SITE_URL}${localizedHref(locale)}`,
    description: t.softwareDescription,
    offers: {
      "@type": "Offer",
      price: "0",
      priceCurrency: "USD",
    },
    inLanguage: locale,
  };

  const orgLd = {
    "@context": "https://schema.org",
    "@type": "Organization",
    name: SITE_NAME,
    url: SITE_URL,
    logo: `${SITE_URL}/logo-transparent.png`,
  };

  return (
    <>
      <JsonLd data={softwareLd} />
      <JsonLd data={orgLd} />

      <section className="heroBleed" aria-label={t.heroAria}>
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
              <span className="heroTagline">{TAGLINE}</span>
            </h1>
            <p className="heroLead">{t.lead}</p>
            <div className="heroActions">
              <Link className="btn" href={localizedHref(locale, "/download")}>
                {t.ctaDownload}
              </Link>
              <Link className="btnGhost" href={localizedHref(locale, "/features")}>
                {t.ctaFeatures}
              </Link>
            </div>
          </div>
          <div className="heroVisual">
            <LiveChatPhone />
          </div>
        </div>
      </section>

      <section className="section">
        <h2>{t.privacyTitle}</h2>
        <p className="muted prose">{t.privacyP1}</p>
        <p className="muted prose" style={{ marginTop: "0.75rem" }}>
          {t.privacyP2Before} <strong>{t.privacyP2P2p}</strong> {t.privacyP2Mid}{" "}
          <strong>{t.privacyP2Relay}</strong> {t.privacyP2After}
        </p>
      </section>

      <section className="section">
        <h2>{t.platformsTitle}</h2>
        <ul className="platformList">
          {PLATFORM_IDS.map((id) => (
            <li key={id}>
              <span>{platforms[id]}</span>
              <span className="muted">{platforms.comingSoon}</span>
            </li>
          ))}
        </ul>
      </section>
    </>
  );
}
