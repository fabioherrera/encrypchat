import type { MetadataRoute } from "next";
import { locales, type Locale } from "@/i18n/config";
import { getDictionary } from "@/i18n/getDictionary";
import { APP_PATHS, localizedHref, type AppPath } from "@/i18n/path";
import { SITE_URL } from "@/lib/site";

export const dynamic = "force-static";

/**
 * The legal pages carry the date they were last edited, so the sitemap can quote
 * it. The rest have no such date, and stamping the build time on them told search
 * engines the whole site changed on every deploy — a claim that, repeated, gets
 * `lastmod` discarded for every URL. Omitting it is allowed and honest.
 */
function lastModified(locale: Locale, path: AppPath): string | undefined {
  const dict = getDictionary(locale);
  switch (path) {
    case "/privacy":
      return dict.privacy.updatedIso;
    case "/terms":
      return dict.terms.updatedIso;
    case "/security":
      return dict.security.updatedIso;
    default:
      return undefined;
  }
}

export default function sitemap(): MetadataRoute.Sitemap {
  return APP_PATHS.flatMap((path) =>
    locales.map((locale) => {
      const languages: Record<string, string> = {};
      for (const loc of locales) {
        languages[loc] = `${SITE_URL}${localizedHref(loc, path)}`;
      }
      languages["x-default"] = `${SITE_URL}${localizedHref("en", path)}`;

      return {
        url: `${SITE_URL}${localizedHref(locale, path)}`,
        lastModified: lastModified(locale, path),
        changeFrequency: path === "" ? "weekly" : "monthly",
        priority: path === "" ? 1 : 0.7,
        alternates: { languages },
      };
    }),
  );
}
