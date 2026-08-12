import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { LegalArticle } from "@/components/LegalArticle";
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

  return <LegalArticle doc={t} locale={locale} path="/privacy" />;
}
