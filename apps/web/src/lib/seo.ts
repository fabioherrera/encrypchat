import type { Metadata } from "next";
import type { Locale } from "@/i18n/config";
import { getDictionary } from "@/i18n/getDictionary";
import { hreflangLanguages, type AppPath } from "@/i18n/path";
import { SITE_NAME, SITE_URL, TAGLINE } from "@/lib/site";

type PageMetaInput = {
  locale: Locale;
  path: AppPath;
  title?: string;
  description?: string;
};

export function buildPageMetadata({
  locale,
  path,
  title,
  description,
}: PageMetaInput): Metadata {
  const dict = getDictionary(locale);
  const canonical = `/${locale}${path}`;
  const pageTitle = title ?? dict.meta.titleDefault;
  const pageDescription = description ?? dict.meta.description;
  const absolute = `${SITE_URL}${canonical}`;

  return {
    title: title
      ? { absolute: `${title} · ${SITE_NAME}` }
      : { absolute: dict.meta.titleDefault },
    description: pageDescription,
    keywords: dict.meta.keywords,
    alternates: {
      canonical,
      languages: hreflangLanguages(path),
    },
    openGraph: {
      type: "website",
      url: absolute,
      title: pageTitle.includes(SITE_NAME) ? pageTitle : `${pageTitle} · ${SITE_NAME}`,
      description: pageDescription,
      siteName: SITE_NAME,
      locale: dict.meta.ogLocale,
      alternateLocale: locale === "en" ? ["es_ES"] : ["en_US"],
      images: [
        {
          url: "/og.png",
          width: 1200,
          height: 630,
          alt: `${SITE_NAME} logo — ${TAGLINE}`,
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title: pageTitle.includes(SITE_NAME) ? pageTitle : `${pageTitle} · ${SITE_NAME}`,
      description: pageDescription,
      images: ["/og.png"],
    },
  };
}
