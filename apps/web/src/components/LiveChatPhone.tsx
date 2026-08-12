import Image from "next/image";
import styles from "./LiveChatPhone.module.css";

type Delay = "a" | "b" | "c" | "d" | "e" | "f" | "g";

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
  src: string;
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

const PEER = {
  name: "María Ruiz",
  avatar: "/demo/avatar-maria.jpg",
};

const SELF = {
  avatar: "/demo/avatar-self.jpg",
};

/** Hilo: quedar en el café → fotos → video de la calle → videollamada P2P */
const messages: Msg[] = [
  {
    id: "m1",
    kind: "text",
    side: "in",
    text: "¿Seguimos con el café de la esquina a las 10?",
    meta: "9:38",
    delay: "a",
  },
  {
    id: "m2",
    kind: "text",
    side: "out",
    text: "Dale. ¿Sigue abierta la terraza?",
    meta: "9:39",
    ticks: "read",
    delay: "b",
  },
  {
    id: "m3",
    kind: "image",
    side: "in",
    src: "/demo/cafe-exterior.jpg",
    alt: "Fachada del café",
    caption: "Acabo de pasar — terraza libre",
    meta: "9:41",
    delay: "c",
  },
  {
    id: "m4",
    kind: "image",
    side: "out",
    src: "/demo/cafe-mesa.jpg",
    alt: "Mesa con café",
    caption: "Perfecto, agarro esa mesa",
    meta: "9:42",
    ticks: "read",
    delay: "d",
  },
  {
    id: "m5",
    kind: "video",
    side: "out",
    src: "/demo/calle-video.jpg",
    alt: "Calle hacia el café",
    caption: "Salgo ya — así se llega",
    meta: "9:43",
    ticks: "read",
    delay: "e",
    duration: "0:18",
  },
  {
    id: "m6",
    kind: "text",
    side: "in",
    text: "Te veo mejor por video un segundo — se me cruzó el mapa",
    meta: "9:44",
    delay: "f",
  },
  {
    id: "m7",
    kind: "call",
    label: "Videollamada P2P",
    detail: "2:14 · cifrado en dispositivo",
    delay: "g",
  },
];

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

export function LiveChatPhone() {
  return (
    <div className={styles.stage} aria-hidden="true">
      <div className={styles.phone}>
        <div className={styles.notch} />
        <div className={styles.screen}>
          <header className={styles.topBar}>
            <span className={styles.back} />
            <span className={styles.avatar}>
              <Image
                src={PEER.avatar}
                alt=""
                width={40}
                height={40}
                className={styles.avatarImg}
              />
            </span>
            <div className={styles.peer}>
              <strong>{PEER.name}</strong>
              <span className={styles.status}>
                <i className={styles.dot} />
                P2P · en línea
              </span>
            </div>
            <div className={styles.actions}>
              <span className={styles.actionCall} />
              <span className={styles.actionVideo} />
            </div>
          </header>

          <div className={styles.thread}>
            <div className={styles.day}>Hoy</div>
            <p className={styles.e2ee}>
              <span className={styles.lock} />
              Cifrado E2EE · en este dispositivo
            </p>

            {messages.map((m) => {
              if (m.kind === "call") {
                return (
                  <div
                    key={m.id}
                    className={`${styles.callCard} ${styles[`delay_${m.delay}`]}`}
                  >
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
                    className={`${styles.bubble} ${styles.mediaBubble} ${styles[m.side]} ${styles[`delay_${m.delay}`]}`}
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
                    className={`${styles.bubble} ${styles.mediaBubble} ${styles[m.side]} ${styles[`delay_${m.delay}`]}`}
                  >
                    <div className={`${styles.mediaThumb} ${styles.videoThumb}`}>
                      <Image
                        src={m.src}
                        alt={m.alt}
                        width={320}
                        height={240}
                        className={styles.mediaImg}
                      />
                      <span className={styles.play} />
                      <span className={styles.duration}>{m.duration}</span>
                    </div>
                    {m.caption ? <p>{m.caption}</p> : null}
                    <MessageMeta meta={m.meta} ticks={m.ticks} />
                  </div>
                );
              }

              return (
                <div
                  key={m.id}
                  className={`${styles.bubble} ${styles[m.side]} ${styles[`delay_${m.delay}`]}`}
                >
                  <p>{m.text}</p>
                  <MessageMeta meta={m.meta} ticks={m.ticks} />
                </div>
              );
            })}
          </div>

          <div className={styles.composer}>
            <div className={styles.field}>
              <span className={styles.clip} />
              <span className={styles.draft}>
                <span className={styles.draftText}>Estoy abajo</span>
                <span className={styles.caret} />
              </span>
            </div>
            <button type="button" className={styles.send} tabIndex={-1} />
          </div>

          {/* Videollamada P2P — overlay realista al final del ciclo */}
          <div className={styles.videoCall}>
            <Image
              src="/demo/call-remote.jpg"
              alt=""
              fill
              className={styles.videoCallRemote}
              sizes="288px"
            />
            <div className={styles.videoCallScrim} />
            <div className={styles.videoCallTop}>
              <span className={styles.videoCallPeer}>{PEER.name}</span>
              <span className={styles.videoCallBadge}>
                <i className={styles.dot} />
                P2P · 02:14
              </span>
            </div>
            <div className={styles.videoCallPip}>
              <Image
                src={SELF.avatar}
                alt=""
                width={72}
                height={96}
                className={styles.videoCallPipImg}
              />
            </div>
            <div className={styles.videoCallControls}>
              <span className={styles.vcMute} />
              <span className={styles.vcEnd} />
              <span className={styles.vcCam} />
            </div>
            <p className={styles.videoCallHint}>Cifrado en este dispositivo</p>
          </div>
        </div>
      </div>
    </div>
  );
}
