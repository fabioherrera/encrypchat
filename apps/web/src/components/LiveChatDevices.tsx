import Image from "next/image";
import type { Dictionary } from "@/i18n/types";
import { DemoChatVideo } from "./DemoChatVideo";
import { DemoVideoCall } from "./DemoVideoCall";
import styles from "./LiveChatDevices.module.css";

const CALL_REMOTE = {
  poster: "/demo/call-remote.jpg",
  mp4: "/demo/call-remote.mp4",
  webm: "/demo/call-remote.webm",
};

const CALL_SELF = {
  poster: "/demo/call-self.jpg",
  mp4: "/demo/call-self.mp4",
  webm: "/demo/call-self.webm",
};

type Delay = "a" | "b" | "c" | "d" | "e" | "f" | "g";
type DemoCopy = Dictionary["demo"];

type TextMsg = {
  id: string;
  kind: "text";
  side: "in" | "out";
  text: string;
  meta: string;
  ticks?: "read" | "pending";
  delay: Delay;
};

type ImageMsg = {
  id: string;
  kind: "image";
  side: "in" | "out";
  src: string;
  alt: string;
  caption?: string;
  meta: string;
  ticks?: "read";
  delay: Delay;
};

type VideoMsg = {
  id: string;
  kind: "video";
  side: "in" | "out";
  poster: string;
  mp4: string;
  webm: string;
  alt: string;
  caption?: string;
  meta: string;
  ticks?: "read";
  delay: Delay;
  duration: string;
};

type CallMsg = {
  id: string;
  kind: "call";
  label: string;
  detail: string;
  delay: Delay;
};

type Msg = TextMsg | ImageMsg | VideoMsg | CallMsg;

const PEER_AVATAR = "/demo/avatar-maria.jpg";

function buildPhoneMessages(t: DemoCopy): Msg[] {
  return [
    {
      id: "m1",
      kind: "text",
      side: "in",
      text: t.m1,
      meta: "9:38",
      delay: "a",
    },
    {
      id: "m2",
      kind: "text",
      side: "out",
      text: t.m2,
      meta: "9:39",
      ticks: "read",
      delay: "b",
    },
    {
      id: "m3",
      kind: "image",
      side: "in",
      src: "/demo/cafe-exterior.jpg",
      alt: t.m3Alt,
      caption: t.m3Caption,
      meta: "9:41",
      delay: "c",
    },
    {
      id: "m4",
      kind: "image",
      side: "out",
      src: "/demo/cafe-mesa.jpg",
      alt: t.m4Alt,
      caption: t.m4Caption,
      meta: "9:42",
      ticks: "read",
      delay: "d",
    },
    {
      id: "m5",
      kind: "video",
      side: "out",
      poster: "/demo/calle-video.jpg",
      mp4: "/demo/calle-video.mp4",
      webm: "/demo/calle-video.webm",
      alt: t.m5Alt,
      caption: t.m5Caption,
      meta: "9:43",
      ticks: "read",
      delay: "e",
      duration: "0:05",
    },
    {
      id: "m6",
      kind: "text",
      side: "in",
      text: t.m6,
      meta: "9:44",
      delay: "f",
    },
    {
      id: "m7",
      kind: "call",
      label: t.callLabel,
      detail: t.callDetail,
      delay: "g",
    },
  ];
}

function buildSidebar(t: DemoCopy) {
  return [
    {
      name: t.peerName,
      preview: t.s3Caption,
      time: "9:43",
      active: true,
      avatar: PEER_AVATAR,
    },
    {
      name: t.diegoName,
      preview: t.diegoPreview,
      time: t.yesterday,
      active: false,
      avatar: "/demo/avatar-diego.jpg",
    },
    {
      name: t.anaName,
      preview: t.anaPreview,
      time: t.mondayShort,
      active: false,
      avatar: "/demo/avatar-ana.jpg",
    },
  ];
}

function MessageMeta({
  meta,
  ticks,
}: {
  meta: string;
  ticks?: "read" | "pending";
}) {
  return (
    <footer>
      <time>{meta}</time>
      {ticks === "read" ? <span className={styles.ticks}>✓✓</span> : null}
      {ticks === "pending" ? <span className={styles.clock}>◷</span> : null}
    </footer>
  );
}

function ThreadMessages({
  items,
  animate,
}: {
  items: Msg[];
  animate: boolean;
}) {
  return (
    <>
      {items.map((m) => {
        const delayClass = animate ? styles[`delay_${m.delay}`] : styles.staticMsg;

        if (m.kind === "call") {
          return (
            <div key={m.id} className={`${styles.callCard} ${delayClass}`}>
              <span className={styles.callIconVideo} />
              <div className={styles.callCopy}>
                <strong>{m.label}</strong>
                <span>{m.detail}</span>
              </div>
              <span className={styles.callPulse} />
            </div>
          );
        }

        if (m.kind === "image") {
          return (
            <div
              key={m.id}
              className={`${styles.bubble} ${styles.mediaBubble} ${styles[m.side]} ${delayClass}`}
            >
              <div className={styles.mediaThumb}>
                <Image
                  src={m.src}
                  alt={m.alt}
                  width={320}
                  height={240}
                  className={styles.mediaImg}
                />
              </div>
              {m.caption ? <p>{m.caption}</p> : null}
              <MessageMeta meta={m.meta} ticks={m.ticks} />
            </div>
          );
        }

        if (m.kind === "video") {
          return (
            <div
              key={m.id}
              className={`${styles.bubble} ${styles.mediaBubble} ${styles[m.side]} ${delayClass}`}
            >
              <DemoChatVideo
                poster={m.poster}
                mp4={m.mp4}
                webm={m.webm}
                label={m.alt}
                duration={m.duration}
              />
              {m.caption ? <p>{m.caption}</p> : null}
              <MessageMeta meta={m.meta} ticks={m.ticks} />
            </div>
          );
        }

        return (
          <div
            key={m.id}
            className={`${styles.bubble} ${styles[m.side]} ${delayClass}`}
          >
            <p>{m.text}</p>
            <MessageMeta meta={m.meta} ticks={m.ticks} />
          </div>
        );
      })}
    </>
  );
}

function ChatChrome({
  variant,
  showVideoCall,
  copy,
}: {
  variant: "phone" | "tablet" | "desktop";
  showVideoCall: boolean;
  copy: DemoCopy;
}) {
  const thread = buildPhoneMessages(copy);
  const sidebar = buildSidebar(copy);
  const withSidebar = variant === "tablet" || variant === "desktop";

  return (
    <div className={`${styles.screen} ${styles[`screen_${variant}`]}`}>
      {withSidebar ? (
        <aside className={styles.sidebar}>
          <div className={styles.sidebarHead}>{copy.chatsLabel}</div>
          <ul className={styles.sidebarList}>
            {sidebar.map((c) => (
              <li
                key={c.name}
                className={c.active ? styles.sidebarItemActive : styles.sidebarItem}
              >
                <span className={styles.sidebarAvatar}>
                  <Image
                    src={c.avatar}
                    alt=""
                    width={40}
                    height={40}
                    className={styles.avatarImg}
                  />
                </span>
                <span className={styles.sidebarCopy}>
                  <strong>{c.name}</strong>
                  <em>{c.preview}</em>
                </span>
                <time>{c.time}</time>
              </li>
            ))}
          </ul>
        </aside>
      ) : null}

      <div className={styles.pane}>
        <header className={styles.topBar}>
          {variant === "phone" ? <span className={styles.back} /> : null}
          <span className={styles.avatar}>
            <Image
              src={PEER_AVATAR}
              alt=""
              width={40}
              height={40}
              className={styles.avatarImg}
            />
          </span>
          <div className={styles.peer}>
            <strong>{copy.peerName}</strong>
            <span className={styles.status}>
              <i className={styles.dot} />
              {copy.statusOnline}
            </span>
          </div>
          <div className={styles.actions}>
            <span className={styles.actionCall} />
            <span className={styles.actionVideo} />
          </div>
        </header>

        <div className={styles.thread}>
          <div className={styles.day}>{copy.dayToday}</div>
          <p className={styles.e2ee}>
            <span className={styles.lock} />
            {copy.e2eeBanner}
          </p>
          <ThreadMessages items={thread} animate />
        </div>

        <div className={styles.composer}>
          <div className={styles.field}>
            <span className={styles.clip} />
            <span className={styles.draft}>
              <span className={styles.draftText}>{copy.draftText}</span>
              <span className={styles.caret} />
            </span>
          </div>
          <button type="button" className={styles.send} tabIndex={-1} />
        </div>

        {showVideoCall ? (
          <DemoVideoCall
            peerName={copy.peerName}
            youLabel={copy.videoCallYou}
            badge={copy.videoCallBadge}
            hint={copy.videoCallHint}
            remote={CALL_REMOTE}
            self={CALL_SELF}
          />
        ) : null}
      </div>
    </div>
  );
}

/** Hero product mock: phone → tablet → iMac, one at a time. */
export function LiveChatDevices({ copy }: { copy: DemoCopy }) {
  return (
    <div className={styles.stage} aria-hidden="true">
      <div className={styles.scene}>
        {/* iMac — último (solo pantalla); cierra con videollamada */}
        <div className={`${styles.device} ${styles.desktop} ${styles.revealDesktop}`}>
          <div className={styles.imac}>
            <div className={styles.imacScreen}>
              <ChatChrome variant="desktop" showVideoCall copy={copy} />
            </div>
            <div className={styles.imacChin}>
              <span className={styles.imacCam} />
            </div>
          </div>
          <div className={styles.imacStand}>
            <div className={styles.imacNeck} />
            <div className={styles.imacFoot} />
          </div>
        </div>

        {/* Tablet — continúa el mismo hilo */}
        <div className={`${styles.device} ${styles.tablet} ${styles.revealTablet}`}>
          <div className={styles.tabletBody}>
            <ChatChrome variant="tablet" showVideoCall={false} copy={copy} />
          </div>
        </div>

        {/* Phone — abre el hilo */}
        <div className={`${styles.device} ${styles.phone} ${styles.revealPhone}`}>
          <div className={styles.notch} />
          <ChatChrome variant="phone" showVideoCall={false} copy={copy} />
        </div>
      </div>
    </div>
  );
}
