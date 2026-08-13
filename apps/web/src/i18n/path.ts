import type { Locale } from "./config";
import { locales } from "./config";

/** Path without locale prefix, e.g. "", "/features", "/download". */
export type AppPath =
  | ""
  | "/features"
  | "/download"
  | "/faq"
  | "/privacy"
  | "/terms"
  | "/security";

export const APP_PATHS: AppPath[] = [
  "",
  "/features",
  "/download",
  "/faq",
  "/privacy",
  "/terms",
  "/security",
];

export function localizedHref(locale: Locale, path: AppPath = ""): string {
  return `/${locale}${path}`;
}

/** Strip `/en` or `/es` prefix; return path like `/features` or "". */
export function stripLocale(pathname: string): AppPath {
  const parts = pathname.split("/").filter(Boolean);
  if (parts.length === 0) return "";
  if ((locales as readonly string[]).includes(parts[0])) {
    const rest = parts.slice(1).join("/");
    if (!rest) return "";
    return `/${rest}` as AppPath;
  }
  return pathname === "/" ? "" : (pathname as AppPath);
}

export function switchLocaleHref(
  currentLocale: Locale,
  targetLocale: Locale,
  pathname: string,
): string {
  const path = stripLocale(pathname);
  return localizedHref(targetLocale, path);
}

export function hreflangLanguages(path: AppPath = ""): Record<string, string> {
  const map: Record<string, string> = {};
  for (const locale of locales) {
    map[locale] = localizedHref(locale, path);
  }
  map["x-default"] = localizedHref("en", path);
  return map;
}
