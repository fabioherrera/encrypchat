import type { MetadataRoute } from "next";
import { locales } from "@/i18n/config";
import { APP_PATHS, localizedHref } from "@/i18n/path";
import { SITE_URL } from "@/lib/site";

export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();

  return APP_PATHS.flatMap((path) =>
    locales.map((locale) => {
      const languages: Record<string, string> = {};
      for (const loc of locales) {
        languages[loc] = `${SITE_URL}${localizedHref(loc, path)}`;
      }
      languages["x-default"] = `${SITE_URL}${localizedHref("en", path)}`;

      return {
        url: `${SITE_URL}${localizedHref(locale, path)}`,
        lastModified: now,
        changeFrequency: path === "" ? "weekly" : "monthly",
        priority: path === "" ? 1 : 0.7,
        alternates: { languages },
      };
    }),
  );
}
