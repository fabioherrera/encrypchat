import type { Metadata } from "next";
import { notFound } from "next/navigation";
import {
  DownloadReleaseLinks,
  PlatformDownloadList,
} from "@/components/PlatformDownloadList";
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
  const t = getDictionary(raw).download;
  return buildPageMetadata({
    locale: raw,
    path: "/download",
    title: t.metaTitle,
    description: t.metaDescription,
  });
}

export default async function DownloadPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale: raw } = await params;
  if (!isLocale(raw)) notFound();
  const locale: Locale = raw;
  const dict = getDictionary(locale);
  const t = dict.download;

  return (
    <article className="section prose">
      <p className="testingNotice">
        <span className="testingBadge">{t.testingBadge}</span>
        {t.testingLead}
      </p>
      <h1>{t.h1}</h1>
      <p className="muted">{t.intro}</p>
      <PlatformDownloadList labels={dict.platforms} />
      <DownloadReleaseLinks checksums={t.checksums} releasePage={t.releasePage} />
      <p>{t.privateNote}</p>
      <p>{t.unsignedNote}</p>
      <p>{t.androidSideload}</p>
      <p>{t.upgradeNote}</p>
      <p className="muted">{t.sourceNote}</p>
    </article>
  );
}
