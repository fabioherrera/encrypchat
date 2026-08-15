# encrypchat_relay

Blind HTTP mailbox for Encrypchat (Phase 5). Stores **opaque ciphertext** only.

## What the relay sees

| Visible | Not visible |
| --- | --- |
| Destination token (`ec_` + 64 hex) | Message plaintext |
| Blob size (bytes) | Private keys / identity secrets |
| Enqueue / pull timing | Decrypted content of any kind |
| Message id (UUID) | Contact lists or phone numbers |

The relay **never decrypts**. Blobs are ciphertext produced by the client
(`encrypchat_core::seal_sender`, wire format `ECS1`) before enqueue.

## Sender authenticity

Since core `0.8.0` the sender is bound into the blob with a static-static X25519 DH and
verified by the recipient alone (see `docs/ffi-contract.md` → *Sealed sender*). This is
deliberately **not** a relay-side check:

- The relay cannot verify it — the binding is only checkable with the recipient's secret.
- It must not be able to. A sender identity the relay could read would hand it the
  sender↔destination graph, which is exactly the metadata a blind relay must not hold.

So the relay code is unchanged by the fix: it still accepts any blob for any destination
and stays blind. What changed is that a forged sender no longer survives on the recipient
side. Anti-abuse at the relay therefore remains what it was — per-IP rate limits and the
per-destination quota — and cannot become sender-based without breaking blindness.

## Public Encrypchat relay

The Flutter client ships `https://relay.encrypchat.com` as the default mailbox
so two devices can exchange sealed messages and contact intros without sharing
a LAN. P2P is still tried first; this mailbox is only the fallback. You can
point ☁ at your own URL (both devices must match) or turn it off (LAN only).

Deploy the public instance as its own Dokploy service:

1. **Commit and push** `deploy/relay/` and `services/relay/Dockerfile` — Dokploy
   clones GitHub, not your laptop.
2. **Dokploy** → Docker Compose → compose path (relative):
   `deploy/relay/docker-compose.yml`
   Never an absolute `/home/iofab/...` path. Add domain `relay.encrypchat.com`
   on service `relay`. Details: [`deploy/relay/README.md`](../../deploy/relay/README.md).
3. Env: `ENCRYPCHAT_RELAY_TRUSTED_PROXIES=127.0.0.1,::1,172.16.0.0/12`
4. Cloudflare Zero Trust → same tunnel → public hostname
   `relay.encrypchat.com` → `http://dokploy-traefik:80`.
5. Check `https://relay.encrypchat.com/healthz` answers `200`.

The app can still point at another URL, or turn the relay off (LAN-only).
Both devices must use the **same** mailbox URL. P2P stays first either way.

## Run your own (small group)

Same binary. 1 vCPU / 1 GB is enough for a handful of devices. Keep the
1 GiB pending default unless you expect offline photos.

```bash
# both apps: Chats → ☁ → http://YOUR_IP:8787  (HTTPS in production)
cargo run -p encrypchat_relay
```

Or `deploy/relay/docker-compose.yml` on a VPS. HTTPS in front (Caddy/nginx/Traefik).
Set `ENCRYPCHAT_RELAY_TRUSTED_PROXIES` if you terminate TLS on a proxy.

## Run

```bash
# defaults: 0.0.0.0:8787, ./data/relay.sqlite
cargo run -p encrypchat_relay

ENCRYPCHAT_RELAY_ADDR=127.0.0.1:8787 \
ENCRYPCHAT_RELAY_DB=/var/lib/encrypchat/relay.sqlite \
cargo run -p encrypchat_relay
```

## Behind a reverse proxy — required configuration

**If you deploy this behind cloudflared, Traefik, nginx or anything else, you must do both of
these.** The repo's own deployment (`deploy/cloudflared/`) is proxied, so this is the normal
case, not the exotic one.

1. **Set `ENCRYPCHAT_RELAY_TRUSTED_PROXIES`** to the address(es) the proxy connects from —
   plain addresses or CIDR blocks, comma separated. Without it every request looks like it
   comes from the proxy, all users share one rate-limit bucket, and a single client can spend
   everyone's budget and get the whole relay answering `429`. The anti-abuse control becomes
   the cheapest denial of service available against you (F-13 in
   [audit-f10.md](../../docs/audit-f10.md)).
2. **Rate-limit at the proxy too.** The relay's limiter is in-memory and per process: it
   bounds one flood against one instance, not a distributed one, and it cannot see requests
   the proxy has already accepted.

```bash
# cloudflared/Traefik on the same host or docker bridge
ENCRYPCHAT_RELAY_TRUSTED_PROXIES="127.0.0.1,::1,172.18.0.0/16"
```

`X-Forwarded-For` is honoured **only** when the connection itself comes from a listed address,
and only as far back as the list reaches: the relay walks the chain from the right and charges
the first address the operator has not vouched for. A client that appends fake hops cannot
shed the entry its own proxy added. With the variable unset the header is ignored entirely,
because trusting it from anyone would let every client choose its own bucket. A malformed
value aborts startup rather than quietly degrading to "trust nothing".

The relay also watches its own traffic: if the first 100 requests all arrive from one address
and no proxy is configured, it logs a warning naming that address. A log line on the running
system catches the misconfiguration that a paragraph in a README does not.

### Env

| Variable | Default | Meaning |
| --- | --- | --- |
| `ENCRYPCHAT_RELAY_ADDR` | `0.0.0.0:8787` | Listen address |
| `ENCRYPCHAT_RELAY_DB` | `./data/relay.sqlite` | SQLite path |
| `RUST_LOG` | `info` | Tracing filter |
| `ENCRYPCHAT_RELAY_TRUSTED_PROXIES` | *(empty)* | Addresses/CIDRs whose `X-Forwarded-For` is believed. **Required behind a proxy** |
| `ENCRYPCHAT_RELAY_MAX_MSGS` | `200` | Pending blobs per destination token |
| `ENCRYPCHAT_RELAY_MAX_BYTES` | `8388608` | Pending bytes per destination token (8 MiB) |
| `ENCRYPCHAT_RELAY_MAX_TOTAL_BYTES` | `1073741824` | Pending bytes across **all** mailboxes (1 GiB). Public compose sets 8 GiB |
| `ENCRYPCHAT_RELAY_ENQUEUE_RPM` | `60` | `enqueue` requests per minute, per client IP |
| `ENCRYPCHAT_RELAY_CHALLENGE_RPM` | `120` | `challenge` (and `pull`) requests per minute, per client IP |
| `ENCRYPCHAT_RELAY_PULL_LEASE_SECS` | `60` | How long a delivered blob is hidden before its second and last delivery. Under 20 s warns at startup — see [Delivery](#delivery-is-at-least-once-twice-at-most) |

Unparseable numbers fall back to the default and log a warning; an unparseable proxy list is
fatal.

## Abuse limits

### Per-destination quota — and why a full mailbox still answers `200`

`enqueue` counts the non-expired blobs already queued for the destination — under the same lock
as the insert, so concurrent writers cannot both slip past the ceiling — and when the new blob
would exceed either the message or the byte limit it **drops the blob and answers exactly like an
acceptance**: `200`, same body, an `id` that was never stored. Delivered-but-leased blobs are
still counted; the quota comes back when the lease ends and the second delivery deletes them (see
[Delivery](#delivery-is-at-least-once-twice-at-most)).

**Why the drop is silent.** `enqueue` is open to anyone, permanently and by design — sealed
sender authenticates the writer to the *recipient*, never to the relay, so there is nobody to
turn away. A refusal that happened only for a full mailbox was therefore a presence oracle for
any token at all: fill the box (32 blobs of 256 KiB, or 200 small ones, inside one IP's minute of
budget), then poll it with a one-byte blob, and the moment the answer changes is the moment the
recipient collected their mail. Sized probes made it worse than a full/not-full bit — the byte
ceiling let a stranger binary-search how many bytes were pending and watch that number move. That
is a delivery timeline for an arbitrary token, held by anyone who knows it rather than by the
operator. The counters and limits were already kept out of the response; what was left was the
status code, so the status code went too (B-3 in [audit-f5-relay.md](../../docs/audit-f5-relay.md)).

**What it costs, stated rather than assumed.** A sender whose blob was dropped is told it was
accepted. That is a signal the sender never reliably had: this response acknowledges *receipt*,
not storage and not delivery — a blob can already die of TTL, or be pulled by a client that
crashes, with nobody notified either way. Relay delivery is best-effort, P2P is the primary path,
and the relay cannot become authenticated on the send side without becoming a
sender↔destination graph. What genuinely changed is that a loss which used to be loud is now
silent, in the one case where the mailbox is full.

**What is not fixed.** Filling somebody's mailbox still denies them offline delivery for as long
as the attacker keeps it full: legitimate senders' blobs are dropped, and now they cannot tell.
Hiding the oracle does not remove the denial, and eviction is not the answer either (see the next
section). The bound is the same as before: it takes a genuinely full mailbox, it self-heals as
the recipient drains or TTLs expire, and P2P is unaffected.

**Residual, in exchange.** Accepted and dropped differ by one `INSERT`, so a patient attacker
with a stable network path can try to separate them by response time. The whole-store `SUM` runs
before either outcome to keep the cheap part of that difference out, but this is not a
constant-time handler and does not claim to be. An operator who wants the drops visible has them
in the log: `dropped: destination mailbox at quota`, with the blob size and no destination.

### Global storage ceiling — checked first, and still reported

The per-destination quota does not bound the disk: nothing stops anyone from spreading blobs
across tokens they invent, and tokens are free. `ENCRYPCHAT_RELAY_MAX_TOTAL_BYTES` caps the
live bytes in the whole store; over it, `enqueue` returns `507 relay storage unavailable`. A
warning is logged at 90%.

**This ceiling is evaluated before anything about the destination**, and that order is the reason
it can stay visible: "the relay is out of space" is the same fact for every token, so it singles
out no recipient and cannot be probed for anyone's presence. Reversed, a globally full relay
would answer differently depending on whether the addressed mailbox was also full, which is the
oracle above rebuilt out of the other ceiling. Hiding it as well would cost more than it buys: a
relay that is out of disk would become a black hole that reports success to every client, and the
condition is one an operator wants senders to be able to see and act on — pick another relay,
stay on P2P.

**Residual, and it is not nothing:** an attacker who pins the store at its ceiling and holds it
there can use that `507`/`200` boundary as an *aggregate* free-space probe, and sized probes
binary-search how much space just appeared. It is far more expensive than the per-mailbox oracle
was — it means holding a gigabyte of live blobs against a per-IP budget of 60 enqueues a minute
and topping it up as TTLs expire — it is confounded by every other user's traffic, and it only
exists while the relay is in a state the operator is already being warned about. Sizing the disk
so the ceiling stays a backstop rather than a working limit is what keeps it that way.

**Nothing is ever evicted to make room.** The only rows the relay deletes are expired ones and
twice-delivered ones. A pressure policy that dropped live blobs to fit a new one would hand any
stranger a way to expel other people's messages by filling the disk — cheaper and quieter than
the F-8 attack it would replace. Refusing the write is worse for the sender and better for
everyone else: the sender gets a `507` and knows the message did not go through, instead of
someone else's message disappearing in silence.

What the ceiling does buy, stated plainly: it turns "fill the disk until SQLite fails and the
host degrades" into "the relay refuses new blobs and keeps delivering what it already holds",
and it recovers on its own as mailboxes drain and TTLs expire. It does **not** stop a
determined flood from making the relay useless for new messages. Bounding the request rate is
the proxy's job, and sizing the disk is the operator's.

### Per-IP rate limit

In-memory token bucket per client IP, burstable up to the per-minute budget: `enqueue`,
`challenge` and `pull` each have their own bucket. Over budget → `429 Too Many Requests`
(no `Retry-After` header yet; clients back off on their own poll interval). `/healthz` is
not limited.

Limits are per process and per IP, so they bound a direct flood, not a distributed one. Behind
a proxy the client address comes from `X-Forwarded-For`, and **only** if the proxy is declared
— see [Behind a reverse proxy](#behind-a-reverse-proxy--required-configuration). A poisoned
limiter lock fails open: availability over strictness.

## API

### `POST /v1/enqueue`

```json
{ "dest_token": "ec_…", "ttl_secs": 86400, "blob_b64": "…" }
→ { "id": "uuid" }
```

- Token: `ec_` + 64 hex
- Max blob: 256 KiB
- Max TTL: 7 days (clamped)
- `429` over the per-IP rate limit · `507` when the **global** storage ceiling is full
- `200` means the relay took the blob, **not** that it stored it and not that it will be
  delivered: a destination over its quota is answered this way too, with an `id` that names no
  row. See [Per-destination quota](#per-destination-quota--and-why-a-full-mailbox-still-answers-200)
  for why, and what it costs

### `POST /v1/challenge`

```json
{}
→ { "challenge_id": "uuid", "nonce_b64": "…", "eph_pubkey_b64": "…" }
```

Creates a short-lived (2 min) PoP challenge: a relay ephemeral X25519 keypair and a nonce.

**The request body is ignored, and there is no `dest_token`.** A challenge belongs to whoever
asked for it, not to a mailbox. That is what closes F-8: challenges used to be stored one per
destination, so a stranger requesting one for your token overwrote yours and every pull you
attempted failed — your mailbox filled up, further messages for you were refused, and the ones
already queued expired. Since the destination is bound inside the proof anyway, the relay does not need to
know it here, and not knowing it also means `/v1/challenge` no longer reveals which mailbox is
about to be read.

Keep the `challenge_id`: it must come back with the proof.

### `POST /v1/pull`

```json
{ "challenge_id": "uuid", "dest_token": "ec_…", "pubkey_b64": "…", "proof_b64": "…" }
→ { "messages": [ { "id": "…", "blob_b64": "…" } ] }
```

Proof-of-possession (ECDH):

1. Client: `proof = SHA-256("encrypchat-pop-v1" ‖ ECDH(secret, eph_pub) ‖ nonce ‖ token)`
2. Relay: looks up `challenge_id`, recomputes with `ECDH(eph_secret, client_pub)`, constant-time compare
3. On success: consume the challenge, return every deliverable blob for the token, and **lease**
   the ones being delivered for the first time / **delete** the ones being delivered for the
   second — see [Delivery](#delivery-is-at-least-once-twice-at-most). Blobs leased by an earlier
   pull are not returned

The response shape is unchanged by the lease, and so is the client contract: a repeated blob
arrives with the same relay `id` and the same `msg_id` inside it.

A failed proof does **not** consume the challenge — ids are unguessable, so the only party who
can spend one is the party it was issued to, and burning it on failure would just hand back a
smaller version of F-8. A successful one always does, so a proof captured in transit cannot be
replayed.

`401` covers both "no such challenge" and "bad proof". Helpers:
`encrypchat_core::pop_proof` / `pop_verify`, FFI `encrypchat_pop_proof`.

### `GET /healthz`

`200` if process is up.

## Storage

SQLite tables:

- `mailbox(id, dest_token, blob, expires_at, created_at, leased_until)`
- `challenges(id, eph_secret, eph_pub, nonce, expires_at)`

Expired rows purged on request and every 60s in the background. Live challenges are capped
globally (50 000, oldest trimmed first) — the cap is deliberately not per token, because a
per-token ceiling is the F-8 weapon whichever way you resolve it: evict the oldest and an
attacker races your challenge out, refuse when full and the attacker locks you out.

**Upgrading:** a `challenges` table from before this change (keyed by `dest_token`) is dropped
on first start. Challenges live two minutes and cost one round trip to replace, so there is
nothing worth migrating. A `mailbox` table from before the lease gains `leased_until` in place,
and the mail already in it is kept: every such row is undelivered by definition, because the
old `pull` deleted whatever it returned.

### Delivery is at-least-once, twice at most

A blob is not deleted when it is delivered. It is **leased**: hidden for
`ENCRYPCHAT_RELAY_PULL_LEASE_SECS` (60 s), then offered one more time, and that second delivery
deletes it.

| `leased_until` | State | What the next pull does |
| --- | --- | --- |
| `NULL` | never delivered | returns it, sets the lease |
| in the future | delivered, hidden | skips it |
| in the past | delivered, lease over | returns it again and **deletes** it |

This closes the loss the README used to declare: a client killed between the `200` and its own
commit — the ordinary case on mobile, where pulls happen on resume and in background fetches —
finds the message waiting when it comes back. It relies on the client de-duplicating by the
`msg_id` inside the blob, which it does (`insertMessageIfNew`, plus the `seen_sealed` table that
survives restarts). **On a relay this new, a client without that de-duplication would show
duplicates**; that is the direction of the dependency, and it is why the lease landed second.

What it costs, stated plainly:

- **Every relayed blob crosses the wire twice.** The second copy is discarded by the recipient.
  There is no way around it without the relay learning that the client persisted the batch, and
  the only way to tell it that is an explicit ACK — a second round trip with its own
  proof-of-possession, after which nothing is deleted until the client speaks up: mailboxes
  fill, new messages are dropped, the queued ones die of TTL. That is the F-8 harm, re-created on purpose. The
  lease buys durability with bandwidth instead, and the bandwidth cost is bounded at ×2.
- **Two attempts, not unlimited.** A client that dies during *both* deliveries still loses the
  message. This is a bounded improvement, not a delivery guarantee.
- **A recipient that pulls again inside the lease gets nothing.** Deliberate: re-offering leased
  rows on every poll would hand the client the same batch every 8 seconds for the whole lease —
  seven wasted copies instead of one, on the radio and on the operator's egress. The price is
  that a client which lost the first batch waits out the lease before it sees those messages.
  The relay cannot tell that case from a healthy re-poll, or from a second device holding the
  same key: all three present the same proof over the same token.
- **A leased blob still counts** against the per-destination quota and the global ceiling,
  because it still occupies disk. So draining a *full* mailbox frees its quota one lease later
  than it used to, instead of immediately. Excluding leased rows would let a recipient hold
  twice its byte quota just by pulling.
- **The TTL always wins.** A lease never extends `expires_at`; a row whose TTL runs out while
  leased is purged and never gets its second delivery. With a TTL shorter than the lease,
  delivery is still at-most-once.

There is no new way to pin the relay's disk here: writing a lease requires the destination's
private key, and anyone at all can already hold those same bytes for the whole TTL — up to 7
days — simply by enqueueing. A minute of lease is not the lever.

**Why 60 s.** Three times the client's own pull timeout (20 s). Two delivery attempts are only
worth having if they are independent failure trials, and they are independent only once the
first response has either arrived or definitively timed out — a lease shorter than that timeout
can burn both attempts on one stalled connection. The rest is margin for the client to commit
the batch and for two devices' clocks to disagree. Longer buys nothing: the duplicate count is
one either way, so a longer lease only delays recovery (worst case here: lease + one 8 s poll,
so about 68 s) and holds the bytes longer. Values under 20 s log a warning at startup.

An operator watching `pull ok` will see `redelivered=N`: blobs handed out a second time, which
is how clients dying before their commit becomes visible. It names no destination.

See [audit-f5-relay.md](../../docs/audit-f5-relay.md) for the decision trail.

## Tests

```bash
cargo test -p encrypchat_relay
cargo test -p encrypchat_core
```

## Log policy

The relay must not retain "who receives and when". Application logs carry:

| Logged | Never logged |
| --- | --- |
| Message id (UUID), blob size, TTL | `dest_token` (full or truncated) |
| Pull result count, re-delivered count | Pubkeys, proofs, nonces, blob bytes |
| Quota drops (blob size, TTL) | Which mailbox was over quota |

`dest_token` is needed in memory to route and to verify PoP, but it is not written to
logs — a token prefix is still a stable identifier and would rebuild the delivery graph.

Operators: keep `RUST_LOG` at `info` or lower verbosity, do not enable request-body
logging in a reverse proxy, and disable access logs that record request payloads.
Access logs with client IPs are outside the relay; treat them as retained metadata.

## Ops notes

- CORS is permissive for local demos; Flutter clients typically hit a LAN IP (no browser CORS).
- Do not put this process on a path that logs request bodies (blobs are still ciphertext, but size/timing are metadata).
- Rotate or wipe `ENCRYPCHAT_RELAY_DB` if compromised — only undelivered ciphertext is lost, not identity keys.
