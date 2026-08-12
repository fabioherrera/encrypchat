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
  const t = getDictionary(raw).terms;
  return buildPageMetadata({
    locale: raw,
    path: "/terms",
    title: t.metaTitle,
    description: t.metaDescription,
  });
}

export default async function TermsPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale: raw } = await params;
  if (!isLocale(raw)) notFound();
  const locale: Locale = raw;
  const t = getDictionary(locale).terms;

  return (
    <article className="section prose">
      <h1>{t.h1}</h1>
      <p className="muted">{t.stub}</p>

      <h2>{t.serviceTitle}</h2>
      <p>{t.serviceBody}</p>

      <h2>{t.securityTitle}</h2>
      <p>{t.securityBody}</p>

      <h2>{t.availabilityTitle}</h2>
      <p>{t.availabilityBody}</p>

      <h2>{t.useTitle}</h2>
      <p>{t.useBody}</p>
    </article>
  );
}
