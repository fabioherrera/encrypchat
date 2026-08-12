import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { isLocale, type Locale } from "@/i18n/config";
import { getDictionary } from "@/i18n/getDictionary";
import { buildPageMetadata } from "@/lib/seo";
import { PLATFORM_IDS } from "@/lib/site";

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
  const platforms = dict.platforms;

  return (
    <article className="section prose">
      <h1>{t.h1}</h1>
      <p className="muted">{t.intro}</p>
      <ul className="platformList">
        {PLATFORM_IDS.map((id) => (
          <li key={id}>
            <span>{platforms[id]}</span>
            <span className="muted">{platforms.comingSoon}</span>
          </li>
        ))}
      </ul>
      <p>{t.sourceNote}</p>
    </article>
  );
}
