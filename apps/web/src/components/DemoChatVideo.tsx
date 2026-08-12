"use client";

import { useEffect, useRef, useState } from "react";
import styles from "./LiveChatDevices.module.css";

type Props = {
  poster: string;
  mp4: string;
  webm: string;
  label: string;
  duration: string;
};

function isPaintedVisible(el: HTMLElement): boolean {
  let node: HTMLElement | null = el;
  while (node && node !== document.body) {
    const s = getComputedStyle(node);
    if (s.display === "none" || s.visibility === "hidden" || Number(s.opacity) < 0.25) {
      return false;
    }
    node = node.parentElement;
  }
  const rect = el.getBoundingClientRect();
  return rect.width > 8 && rect.height > 8;
}

/**
 * Real demo clip: poster first; media loads only when the parent device is painted.
 * Keeps initial page weight low (poster ~26KB; WebM ~113KB / MP4 ~605KB on demand).
 */
export function DemoChatVideo({ poster, mp4, webm, label, duration }: Props) {
  const rootRef = useRef<HTMLDivElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const [active, setActive] = useState(false);

  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    let cancelled = false;
    let raf = 0;

    const tick = () => {
      if (cancelled) return;
      if (isPaintedVisible(root)) {
        setActive(true);
        return;
      }
      raf = requestAnimationFrame(tick);
    };

    raf = requestAnimationFrame(tick);
    return () => {
      cancelled = true;
      cancelAnimationFrame(raf);
    };
  }, []);

  useEffect(() => {
    const video = videoRef.current;
    if (!active || !video) return;

    const play = () => {
      void video.play().catch(() => {
        /* autoplay may be blocked; poster remains */
      });
    };

    if (video.readyState >= 2) play();
    else video.addEventListener("loadeddata", play, { once: true });
  }, [active]);

  return (
    <div ref={rootRef} className={`${styles.mediaThumb} ${styles.videoThumb}`}>
      <video
        ref={videoRef}
        className={styles.mediaVideo}
        poster={poster}
        muted
        playsInline
        loop
        preload={active ? "metadata" : "none"}
        aria-label={label}
      >
        {active ? (
          <>
            <source src={webm} type="video/webm" />
            <source src={mp4} type="video/mp4" />
          </>
        ) : null}
      </video>
      {!active ? <span className={styles.play} /> : null}
      <span className={styles.duration}>{duration}</span>
    </div>
  );
}
