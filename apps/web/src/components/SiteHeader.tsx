import Link from "next/link";
import Image from "next/image";
import type { Locale } from "@/i18n/config";
import { getDictionary } from "@/i18n/getDictionary";
import { localizedHref } from "@/i18n/path";
import { SITE_NAME } from "@/lib/site";
import { LanguageSwitcher } from "./LanguageSwitcher";
import styles from "./SiteHeader.module.css";

export function SiteHeader({ locale }: { locale: Locale }) {
  const t = getDictionary(locale).nav;
  const links = [
    { href: localizedHref(locale, "/features"), label: t.features },
    { href: localizedHref(locale, "/download"), label: t.download },
    { href: localizedHref(locale, "/faq"), label: t.faq },
  ];

  return (
    <header className={styles.header}>
      <Link href={localizedHref(locale)} className={styles.brand}>
        <Image
          src="/logo-mark.png"
          alt=""
          width={52}
          height={56}
          className={styles.mark}
          priority
        />
        <span className={styles.name}>{SITE_NAME}</span>
      </Link>
      <nav className={styles.nav} aria-label={t.primaryAria}>
        {links.map((l) => (
          <Link key={l.href} href={l.href} className={styles.link}>
            {l.label}
          </Link>
        ))}
        <LanguageSwitcher locale={locale} ariaLabel={t.langSwitcherAria} />
        <Link href={localizedHref(locale, "/download")} className={styles.cta}>
          {t.cta}
        </Link>
      </nav>
    </header>
  );
}
