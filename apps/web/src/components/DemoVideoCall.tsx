"use client";

import { useEffect, useRef, useState } from "react";
import styles from "./LiveChatDevices.module.css";

type Stream = {
  poster: string;
  mp4: string;
  webm: string;
};

type Props = {
  peerName: string;
  youLabel: string;
  badge: string;
  hint: string;
  remote: Stream;
  self: Stream;
};

function isPaintedVisible(el: HTMLElement): boolean {
  let node: HTMLElement | null = el;
  while (node && node !== document.body) {
    const s = getComputedStyle(node);
    if (s.display === "none" || s.visibility === "hidden" || Number(s.opacity) < 0.2) {
      return false;
    }
    node = node.parentElement;
  }
  const rect = el.getBoundingClientRect();
  return rect.width > 8 && rect.height > 8;
}

function LazyMutedVideo({
  stream,
  className,
  label,
}: {
  stream: Stream;
  className: string;
  label: string;
}) {
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
      void video.play().catch(() => {});
    };
    if (video.readyState >= 2) play();
    else video.addEventListener("loadeddata", play, { once: true });
  }, [active]);

  return (
    <div ref={rootRef} className={styles.videoCallMedia}>
      <video
        ref={videoRef}
        className={className}
        poster={stream.poster}
        muted
        playsInline
        loop
        preload={active ? "metadata" : "none"}
        aria-label={label}
      >
        {active ? (
          <>
            <source src={stream.webm} type="video/webm" />
            <source src={stream.mp4} type="video/mp4" />
          </>
        ) : null}
      </video>
    </div>
  );
}

/** Dual-pane muted video call: peer + you, clearly two people. */
export function DemoVideoCall({
  peerName,
  youLabel,
  badge,
  hint,
  remote,
  self,
}: Props) {
  return (
    <div className={styles.videoCall}>
      <div className={styles.videoCallStage}>
        <div className={styles.videoCallTile}>
          <LazyMutedVideo
            stream={remote}
            className={styles.videoCallFeed}
            label={peerName}
          />
          <div className={styles.videoCallTileMeta}>
            <strong>{peerName}</strong>
            <span>
              <i className={styles.dot} />
              {badge}
            </span>
          </div>
        </div>
        <div className={`${styles.videoCallTile} ${styles.videoCallTileSelf}`}>
          <LazyMutedVideo
            stream={self}
            className={styles.videoCallFeed}
            label={youLabel}
          />
          <div className={styles.videoCallTileMeta}>
            <strong>{youLabel}</strong>
          </div>
        </div>
      </div>

      <div className={styles.videoCallControls}>
        <span className={styles.vcMute} />
        <span className={styles.vcEnd} />
        <span className={styles.vcCam} />
      </div>
      <p className={styles.videoCallHint}>{hint}</p>
    </div>
  );
}
