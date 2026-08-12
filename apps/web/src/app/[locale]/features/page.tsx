import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { isLocale, type Locale } from "@/i18n/config";
import { getDictionary } from "@/i18n/getDictionary";
import { localizedHref } from "@/i18n/path";
import { buildPageMetadata } from "@/lib/seo";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale: raw } = await params;
  if (!isLocale(raw)) return {};
  const t = getDictionary(raw).features;
  return buildPageMetadata({
    locale: raw,
    path: "/features",
    title: t.metaTitle,
    description: t.metaDescription,
  });
}

export default async function FeaturesPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale: raw } = await params;
  if (!isLocale(raw)) notFound();
  const locale: Locale = raw;
  const t = getDictionary(locale).features;

  return (
    <article className="section prose">
      <h1>{t.h1}</h1>
      <p className="muted">{t.intro}</p>

      <h2>{t.e2eeTitle}</h2>
      <p>{t.e2eeBody}</p>

      <h2>{t.p2pTitle}</h2>
      <p>{t.p2pBody}</p>

      <h2>{t.zeroCloudTitle}</h2>
      <p>{t.zeroCloudBody}</p>

      <h2>{t.relayTitle}</h2>
      <p>
        {t.relayBodyBefore} <em>{t.relayCiphertext}</em> {t.relayBodyAfter}
      </p>

      <h2>{t.tokenTitle}</h2>
      <p>{t.tokenBody}</p>

      <p>
        <Link className="btn" href={localizedHref(locale, "/download")}>
          {t.cta}
        </Link>
      </p>
    </article>
  );
}
