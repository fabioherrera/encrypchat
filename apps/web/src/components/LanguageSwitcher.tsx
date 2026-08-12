"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { Locale } from "@/i18n/config";
import { locales } from "@/i18n/config";
import { switchLocaleHref } from "@/i18n/path";
import styles from "./SiteHeader.module.css";

export function LanguageSwitcher({
  locale,
  ariaLabel,
}: {
  locale: Locale;
  ariaLabel: string;
}) {
  const pathname = usePathname() || `/${locale}`;

  return (
    <div className={styles.lang} role="navigation" aria-label={ariaLabel}>
      {locales.map((target, i) => {
        const href = switchLocaleHref(locale, target, pathname);
        const active = target === locale;
        return (
          <span key={target} className={styles.langItem}>
            {i > 0 ? <span className={styles.langSep} aria-hidden="true">|</span> : null}
            {active ? (
              <span className={styles.langActive} aria-current="true">
                {target.toUpperCase()}
              </span>
            ) : (
              <Link href={href} className={styles.langLink} hrefLang={target}>
                {target.toUpperCase()}
              </Link>
            )}
          </span>
        );
      })}
    </div>
  );
}
