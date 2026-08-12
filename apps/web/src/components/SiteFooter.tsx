import Link from "next/link";
import type { Locale } from "@/i18n/config";
import { getDictionary } from "@/i18n/getDictionary";
import { localizedHref } from "@/i18n/path";
import { SITE_NAME } from "@/lib/site";
import styles from "./SiteFooter.module.css";

export function SiteFooter({ locale }: { locale: Locale }) {
  const t = getDictionary(locale).footer;

  return (
    <footer className={styles.footer}>
      <p className={styles.brand}>{SITE_NAME}</p>
      <p className={styles.note}>{t.note}</p>
      <nav className={styles.links} aria-label={t.aria}>
        <Link href={localizedHref(locale, "/privacy")}>{t.privacy}</Link>
        <Link href={localizedHref(locale, "/terms")}>{t.terms}</Link>
        <Link href={localizedHref(locale, "/faq")}>{t.faq}</Link>
        <Link href={localizedHref(locale, "/download")}>{t.download}</Link>
      </nav>
    </footer>
  );
}
