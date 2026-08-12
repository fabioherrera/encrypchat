# Auditor review — Phase 5 blind relay

Readonly + post-fix notes (2026-08-12).

**Verdict:** OK for **LAN demo**. Not production-hardened.

## Holds

- Relay stores/returns opaque ciphertext only (client now enqueues E2EE JSON payload, not cleartext EC04)
- **Sender authenticity on the relay path** — core `0.8.0` `ECS1` sealed sender: the
  sender is bound to the content by a static-static X25519 DH and verified by the
  recipient alone. Forging a contact now needs that contact's private key
- PoP ECDH + token↔pubkey bind + one-shot challenge
- TTL + lease-on-pull: a delivered blob is hidden for 60 s, offered once more, then deleted.
  Delivery is **at-least-once, twice at most** (see below)
- Prefer P2P; relay only on PeerOffline
- Call signaling never traverses the relay — the client refuses to enqueue it and
  drops `kind == 'call'` on pull (see `audit-f7-calls.md`)
- Application logs omit `dest_token` (no delivery graph); policy in `services/relay/README.md`
- Per-destination quota (200 blobs / 8 MiB pending, counted under the insert lock) and
  per-IP token bucket on `enqueue` / `challenge` / `pull`; all four values env-tunable
- Enqueue answers the same thing whether it stored the blob or dropped it for quota, so a
  third party cannot read a mailbox's state — or its owner's collection times — off the send
  path (B-3 below). The global disk ceiling is checked first and is still reported

## Open (pre-production)

| Sev | Item |
| --- | --- |
| ~~High~~ | ~~Sender authenticity on relay path not EH01-grade~~ — **closed** by sealed sender (core `0.8.0`), and now in effect: `sealedSeal` / `sealedOpen` are called from `messaging_service.dart` and covered by tests against the real core. Note the original wording was wrong twice over: "EH01-grade" was not a bar to clear, because EH01 did not prove key possession either (F-1 in [audit-f10.md](audit-f10.md)), and the gap was never specific to the relay route — it was the crypto layer authenticating nobody on any path |
| Medium | **Replay of a captured relay blob.** Sealing binds the blob to one sender and one destination, but a byte-for-byte replay still opens. `open_sealed` returns `msg_id` and enforces a 7-day + 300 s freshness window; the client must keep a seen-id set over that window. Core-side only half of the problem, by design |
| ~~Medium~~ | ~~Challenge overwrite DoS~~ — **closed**. Rate limiting was never a mitigation: the whole attack fitted inside the budget. Challenges no longer belong to a destination at all (F-8 in [audit-f10.md](audit-f10.md)) |
| ~~Medium~~ | ~~Delete-before-client-durable-ack~~ — **closed** by the lease. The blocker (client-side `msg_id` de-duplication) landed first, as the order below required. What replaces it is not a delivery guarantee: two attempts, and every relayed blob now crosses the wire twice. Reasoning below |
| ~~Medium~~ | ~~Quota rejection (`507`) is a presence oracle~~ — **closed** for the distinguishability, which was the closable half. It was rated Low as "tells a sender the mailbox is near full", and "near full" does not describe what was learned: a third party who knows a token could fill that mailbox and then poll it, and the transition back to `200` marked the moment the recipient drained it — a delivery timeline for an arbitrary token, plus targeted denial of offline delivery while the box stayed full. `enqueue` staying open to anyone is by design and is not closed; a mailbox over quota now **drops the blob and answers exactly like an acceptance**. The price is a delivery signal the sender never had reliably. Detail below |
| Low | Default HTTP (use TLS off-LAN) — client now shows a persistent warning instead of failing silently |
| Low | **Targeted denial of offline delivery**, the half of B-3 that does not close: keeping someone's mailbox full stops relayed messages reaching them, and since B-3 their senders are not told. Not closable while `enqueue` is open to anyone, and eviction would be worse — it would let a stranger expel accepted messages. Bounded: it takes a genuinely full mailbox, it self-heals on drain or TTL, and P2P is unaffected |
| Low | Response time on `enqueue` still separates a stored blob from a quota-dropped one by one `INSERT`. Statistical, not a code difference; see B-3 for why equalising it was not judged worth the write amplification |
| Low | Rate limits are per process / per IP: no protection against a distributed flood. Behind a proxy the client address now comes from `X-Forwarded-For`, but **only** with `ENCRYPCHAT_RELAY_TRUSTED_PROXIES` configured (F-13); the proxy must still limit as well |

## B-3: the `507` presence oracle — what became opaque, and what did not

The oracle, precisely. `enqueue` is unauthenticated and the quota is per mailbox, so anyone who
knows a token could fill that mailbox — 32 blobs of 256 KiB, or 200 small ones, inside one IP's
60-per-minute budget — and then poll it with a one-byte blob. `507` meant still full, `200` meant
the recipient had drained it. Because leased rows count too, the flip actually marked the
*second* collection. Sized probes made it finer than one bit: since a probe that was refused cost
the attacker nothing — no row, no quota spent — shrinking it until it was accepted narrowed how
many bytes were pending almost for free, and repeating that showed the figure move as mail
arrived. The threat
model attributes collection times to the operator; this handed them to anyone holding a token,
which is invariant 5 on its metadata side.

### What is now opaque: the per-destination quota only

A mailbox over its message or byte quota **drops the blob and answers exactly like an
acceptance** — `200`, same body shape, a fresh v4 `id` that names no row. There is no endpoint
that takes an `id` back, so the two cases are not separable after the fact either.

`enqueue` remains open to anyone, and that is not the closable part: sealed sender authenticates
the writer to the recipient, never to the relay, and a relay that could tell senders apart would
be holding the sender↔destination graph. So the distinguishability is what went.

### What stays visible: the global storage ceiling

Reported as before (`507 relay storage unavailable`), and the store now evaluates it **before**
it looks at the destination at all. The ordering is the argument: "the relay is out of space" is
the same fact for every token, so it singles out no recipient and cannot be probed for anyone's
presence. Checked in the old order, a globally full relay would have answered differently
depending on whether the addressed mailbox was also full — the same oracle rebuilt out of the
other ceiling.

Hiding it too would cost more than it buys. A relay out of disk would become a black hole
reporting success to every client, and that is a condition senders should be able to see and act
on (choose another relay, stay on P2P) rather than one only the operator's log knows about. It
also takes away a legitimate operational signal for no privacy gain, since no recipient is named.

### What the honest sender loses, stated rather than assumed

A sender whose blob was dropped is told it was accepted. **This is judged acceptable**, and the
reason is that the signal was never reliable: the response acknowledges receipt, not storage and
not delivery. A blob can already die of TTL unannounced, or be handed to a client that crashes
before committing it; relay delivery is best-effort by construction and P2P is the primary path.
What genuinely changed is that a loss which used to be loud is now silent, in the one case where
the mailbox is full.

**The client does surface that `507` today, and it would now be lying twice.** Not changed here —
it belongs with the rest of the client work:

- `relay_client.dart` maps `507` to *"Buzón del destinatario lleno en el relay"*. After this
  change `507` only ever means the relay itself is out of disk, so the message names the wrong
  cause and the wrong remedy.
- `messaging_service.dart` treats a successful `enqueue` as `MessageStatus.viaRelay`. A dropped
  blob now takes that path, so the message shows as queued at the relay when nothing was queued.
  Previously the `507` threw and the message was marked `error` with a visible reason.

### What is not fixed by this

The targeted denial is untouched: filling a mailbox still stops offline delivery to that person
for as long as it is kept full, and legitimate senders can no longer tell. Hiding the oracle does
not remove the denial — and the alternative of evicting to make room is worse, since it would let
a stranger expel messages that were already accepted. It stays bounded the way it was: it takes a
genuinely full mailbox, it self-heals as the recipient drains or TTLs expire, and P2P is
unaffected.

### Other channels of the same kind

- **Response time on `enqueue` (open, not closed).** Accepted and dropped now differ by one
  `INSERT` and its commit. The whole-store `SUM` was moved ahead of both outcomes so it is not
  part of the difference, but this is not a constant-time handler and does not claim to be. A
  patient attacker on a stable path could try to separate the two statistically. Closing it
  properly means equal work on both branches — a write-then-delete on the drop path — which buys
  an attacker free write amplification; not judged worth it at this severity.
- **The global ceiling as an aggregate probe (open, accepted).** Pinned at its ceiling, the
  `507`/`200` boundary reports whether space was freed anywhere in the store, and sized probes
  binary-search how much. Far more expensive than the per-mailbox oracle — a gigabyte of live
  blobs held against a 60-per-minute budget and topped up as TTLs expire — confounded by every
  other user's traffic, and only present while the relay is in a state the operator is already
  warned about. Sizing the disk so the ceiling stays a backstop is what keeps it there.
- **`pull` is clean for a third party.** Every refusal on that path is decided before the mailbox
  is read: the token↔pubkey check runs in the handler, and `pull_with_pop` verifies the proof and
  returns `pop failed` before it selects a single row. So a stranger's `401` carries nothing about
  mailbox state, in the code or in the time it takes.
- **`challenge` names no destination** since F-8, so it cannot be probed per token at all.

## Delete-before-durable-ack: the decision, and what shipped

`pull` used to return the blobs and delete them in one transaction. If the app died between the
`200` and its own commit, the message was gone and nobody learned of it. On mobile this is not
theoretical: pulls happen on resume and in background fetches, which is exactly when the OS
kills apps.

The decision was to leave it until the client de-duplicated by `msg_id`, because both candidate
fixes needed that first and shipping either one earlier would have traded a rare silent loss for
a certain visible defect. That dependency is now met — inbound messages go through
`insertMessageIfNew` on the `msg_id` in both routes, a repeat neither rewrites the row nor
refreshes its `createdAt`, and `seen_sealed` survives restarts — so the lease shipped.

### What shipped

Rows carry `leased_until`. A pull returns everything not expired and not currently leased; rows
delivered for the first time get `leased_until = now + 60 s`, rows whose lease had already run
out get returned again **and deleted**. No API change, no new endpoint, no second round trip:
the response shape and the client contract are untouched.

**A recipient that pulls again inside the lease is served nothing.** This was the real decision,
because a healthy client comes back every 8 s and that is the normal case, not the exception.
The structural point in the original analysis stands — the window in which a crashed client
recovers is the window in which a healthy one sees a message twice, and you cannot have one
without the other — but it has a knob: *how many* times. Hiding leased rows does not remove the
duplicate, it caps it at exactly one, where re-offering them on every poll would cost
`lease / 8` ≈ 7 copies of the batch. For an 8 MiB mailbox that is the difference between one
wasted transfer and seven, on the radio and on the operator's egress. The price of hiding is
that a client which lost the first batch waits out the lease. The relay cannot distinguish that
client from a healthy re-poll or from a second device holding the same key, so it is one
decision covering all three.

**60 s**, and the reasoning is the client's own loop: it polls every 8 s with a 20 s timeout on
the pull. Two delivery attempts are only worth having if they are independent failure trials,
and they are independent only after the first response has either arrived or definitively timed
out — a lease under 20 s can burn both attempts on one stalled connection, which is the exact
failure being fixed. 60 s is 3× that, leaving margin for the client to commit a 200-blob batch
on a cold phone and for two devices' clocks to disagree. Longer buys nothing, since the
duplicate count is one either way: it only delays recovery (worst case lease + one poll ≈ 68 s)
and holds bytes longer. Under 20 s logs a warning at startup.

### Interaction with the F-13 disk ceiling

A leased blob occupies disk, so it is counted — by the per-destination quota and by the global
byte ceiling alike. The consequence is a regression on the send path: draining a *full*
mailbox now frees its quota one lease later instead of immediately, so blobs sent into that window
are still dropped for up to a minute after the recipient has read everything — silently, since
B-3. Accepted, and bounded: it only
happens at 200 blobs / 8 MiB, and it self-heals. The alternative — excluding leased rows from
the quota — would let a recipient hold twice its byte quota by pulling, which is a worse
property than a self-healing minute.

**A flood of expired leases cannot happen**, which was the second-order worry. Writing a lease
requires a proof of possession of the destination key, so nobody can create leases on somebody
else's mailbox; and anyone at all can already hold the same bytes for the full TTL — up to 7
days — just by enqueueing, no proof of anything required. A minute of lease is not the lever,
the TTL is. The lease also never touches `expires_at`, so it can never hold a row past its TTL:
a row that expires while leased is purged and never gets its second delivery, which means that
with a TTL shorter than the lease delivery is still at-most-once.

### What was not built, and why

*Explicit ACK* (`POST /v1/ack`): needs its own proof-of-possession, or anyone could delete your
mailbox. That is a second endpoint, a second PoP round trip, and lease state anyway. And until
the client sends it, nothing is ever deleted: mailboxes fill, later messages are dropped, the
queued ones expire — precisely the F-8 harm closed in the same pass. The lease buys durability with bandwidth
instead: every relayed blob crosses the wire twice, bounded at ×2, and the second copy is
discarded by the recipient's de-duplication.

An implicit ACK was considered and rejected as **wrong, not merely unwanted**: treating "the
same recipient pulled again" as proof that the previous batch was persisted looks free, but a
client that dies before its commit and restarts issues exactly that pull — `startNode` fires one
immediately — so the evidence is strongest in the one case where it is false. It would delete
the batch it was supposed to protect.

### Residual

- Two attempts only. A client that dies during both deliveries still loses the message. Bounded
  improvement, not a guarantee, and the README says so.
- Bandwidth ×2 on the relay path for relayed messages. P2P is unaffected.
- A relay this new in front of a client without `msg_id` de-duplication would show duplicates.
  That is the direction of the dependency; the client shipped first.

## P0 before public relay operators

1. ~~Bind/sign sender on relay payloads~~ — **done in core** (`ECS1` sealed sender,
   `api_version` `0.8.0`, [ffi-contract.md](ffi-contract.md#sealed-sender-relay-payloads-080)).
   Not signed but *designated-verifier authenticated*: X25519 cannot sign, and a public
   signature would make every blob transferable proof of who wrote to whom. The client wiring
   that this depended on has landed  
2. TLS  
3. ~~Rate-limit challenges~~ — **done**: per-IP token bucket on `challenge`, `pull` and
   `enqueue`, plus a per-destination mailbox quota (`ENCRYPCHAT_RELAY_*`). Note this was
   *listed* as the mitigation for the challenge-overwrite DoS and never was one — the attack
   fitted inside the budget. What closed it was removing the per-destination challenge (F-8)  
4. Behind a proxy, `ENCRYPCHAT_RELAY_TRUSTED_PROXIES` set and rate limiting at the proxy.
   Without it the per-IP limit charges every user to one bucket (F-13)  

## Still open after the sealed-sender fix

| Owner | Item |
| --- | --- |
| ~~Client~~ | ~~Wire `encrypchat_sealed_seal` / `encrypchat_sealed_open` into the relay path and drop the `from` field from the payload~~ — **done**: `messaging_service.dart` seals on the way out and opens on the way in, with tests against the real core. The break landed with it: an unsealed blob is rejected with `InvalidFrame` (10), a forged one with `AuthFailed` (11) |
| ~~Client~~ | ~~Keep a `msg_id` seen-set over the freshness window~~ — **done**, and with it the prerequisite for the lease. It is now load-bearing for delivery, not only for replay: with the lease in place the relay hands the same blob over twice on the recovery path by design |
| ~~Client~~ | ~~New challenge contract (F-8)~~ — **done**: `relay_client.dart` posts an empty body to `/v1/challenge`, keeps the `challenge_id` and sends it back on `/v1/pull`. It also refuses a `200` without an id, so a pre-F-8 relay is named instead of producing a `401` every 8 s |
| Client | B-3 fallout on the send path, both now wrong: `relay_client.dart` maps `507` to *"Buzón del destinatario lleno en el relay"*, but `507` now means only that the relay is out of disk; and a blob dropped by the destination's quota gets a `200`, so `messaging_service.dart` marks the message `viaRelay` when nothing was queued (it used to mark it `error` with a reason). Whether a best-effort send should say anything at all is a client decision — see [B-3](#b-3-the-507-presence-oracle--what-became-opaque-and-what-did-not) for why the relay cannot tell it apart |
| ~~Relay~~ | ~~Delete-before-durable-ack~~ — **done**: lease on pull, second delivery deletes. See the section above for the cost |
| Client | Two stale comments on the relay path, now that blobs are leased rather than deleted: `pullFromRelay` says "blobs are already deleted relay-side" when justifying that one bad blob must not drop the rest (still the right behaviour — a dropped blob does come back once — but for a different reason), and the drop counted as `InboundDropReason.replay` on a repeat is now an expected event on the recovery path rather than a sign of an attack |
| Operator | `ENCRYPCHAT_RELAY_TRUSTED_PROXIES` in the proxied deployment, and rate limiting at the proxy (F-13) |
| Client | Call signaling over the relay is no longer forgeable and may be reconsidered ([audit-f7-calls.md](audit-f7-calls.md)) — but not before replay is closed, since a replayed ring is still a ring. Enabling it is a client decision, not a core one. The P2P-only policy it replaces was never a mitigation: P2P had the same forgery until EH02 (F-1) |
| Relay | TLS off-LAN. Unchanged by this fix |
| ~~Relay~~ | ~~Quota rejection distinguishable from acceptance~~ — **done** (B-3): a quota drop answers like an acceptance, the global ceiling is checked first and still reported. Residual timing channel and the aggregate ceiling probe are written up there |
| Relay | Nothing about sender identity: the relay stays unable to verify who wrote a blob, because a sender identity it could verify is a sender↔destination graph it would hold |
