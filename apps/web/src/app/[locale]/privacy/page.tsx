import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { isLocale, type Locale } from "@/i18n/config";
import { getDictionary } from "@/i18n/getDictionary";
import { buildPageMetadata } from "@/lib/seo";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale: raw } = await params;
  if (!isLocale(raw)) return {};
  const t = getDictionary(raw).privacy;
  return buildPageMetadata({
    locale: raw,
    path: "/privacy",
    title: t.metaTitle,
    description: t.metaDescription,
  });
}

export default async function PrivacyPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale: raw } = await params;
  if (!isLocale(raw)) notFound();
  const locale: Locale = raw;
  const t = getDictionary(locale).privacy;

  return (
    <article className="section prose">
      <h1>{t.h1}</h1>
      <p className="muted">{t.stub}</p>

      <h2>{t.collectTitle}</h2>
      <p>{t.collectBody}</p>

      <h2>{t.deviceTitle}</h2>
      <p>{t.deviceBody}</p>

      <h2>{t.relayTitle}</h2>
      <p>{t.relayBody}</p>

      <h2>{t.siteTitle}</h2>
      <p>{t.siteBody}</p>

      <h2>{t.contactTitle}</h2>
      <p>{t.contactBody}</p>
    </article>
  );
}
