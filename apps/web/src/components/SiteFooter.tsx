import Link from "next/link";
import { SITE_NAME } from "@/lib/site";
import styles from "./SiteFooter.module.css";

export function SiteFooter() {
  return (
    <footer className={styles.footer}>
      <p className={styles.brand}>{SITE_NAME}</p>
      <p className={styles.note}>
        End-to-end encrypted P2P messaging. Optional blind relays store only
        ciphertext until delivery — not your readable chats.
      </p>
      <nav className={styles.links} aria-label="Footer">
        <Link href="/privacy">Privacy</Link>
        <Link href="/terms">Terms</Link>
        <Link href="/faq">FAQ</Link>
        <Link href="/download">Download</Link>
      </nav>
    </footer>
  );
}
