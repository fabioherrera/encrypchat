import Link from "next/link";
import Image from "next/image";
import { SITE_NAME } from "@/lib/site";
import styles from "./SiteHeader.module.css";

const links = [
  { href: "/features", label: "Features" },
  { href: "/download", label: "Download" },
  { href: "/faq", label: "FAQ" },
];

export function SiteHeader() {
  return (
    <header className={styles.header}>
      <Link href="/" className={styles.brand}>
        <Image
          src="/logo.png"
          alt=""
          width={40}
          height={40}
          className={styles.mark}
          priority
        />
        <span className={styles.name}>{SITE_NAME}</span>
      </Link>
      <nav className={styles.nav} aria-label="Primary">
        {links.map((l) => (
          <Link key={l.href} href={l.href} className={styles.link}>
            {l.label}
          </Link>
        ))}
        <Link href="/download" className={styles.cta}>
          Get the app
        </Link>
      </nav>
    </header>
  );
}
