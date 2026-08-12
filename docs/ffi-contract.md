# FFI contract — Encrypchat core ↔ Flutter

Status: **Phase 5 PoP + core blocklist + sealed sender + EH02 handshake + encrypted P2P transport**
(`crates/core` C ABI + `api_version` `0.8.1`).

## Versioning

- Rust crate: `encrypchat_core` `api_version()` → `0.8.1`
- Bump `api_version` whenever exported FFI signatures or wire formats change.
- `0.8.1` adds no symbols and changes no wire format, but it **rejects inputs that used to be
  accepted**, which is why it moves at all. Every X25519 public key entering the core must now be
  canonically encoded — bit 255 clear and the little-endian value below `2^255 - 19` — or the call
  fails with `InvalidPublicKey` (2). RFC 7748 masks and reduces the u-coordinate before every
  Diffie-Hellman, so an alias is the *same key* with a *different* `SHA-256`, and accepting one let
  a blocked peer come back under a token nobody had blocked (F-10). Affects `encrypchat_encrypt`,
  `encrypchat_sealed_seal` and `encrypchat_pop_proof` on their key arguments, and
  `encrypchat_sealed_open` on the sender it recovers. **A canonical key produces exactly the token
  it always did**, so stored identities, contact cards, QRs and blocklist entries are unaffected and
  there is no migration.
- `0.8.0` adds `encrypchat_sealed_seal` / `encrypchat_sealed_open` and error code `13` (`Expired`).
  The **symbols** are additive, but two **wire formats** are not, and both are hard cuts:
  - *Relay payloads.* A blob sealed by `0.8.0` cannot be read by an older client, and an older blob is
    rejected by `encrypchat_sealed_open` with `InvalidFrame` (10) — see *Sealed sender* below.
  - *P2P handshake and transport.* EH01 is replaced by **EH02** (F-1 in
    [audit-f10.md](audit-f10.md): the old proof could be built from the victim's public key), and
    every frame of an established session is now encrypted under a session key derived from it, header
    included (F-15: the `EC04` header used to travel in the clear). No exported signature changes, but a
    `0.7.x` node and a `0.8.0` node cannot connect to each other: the handshake fails on the first
    message with `AuthFailed` (11). **Both ends must ship together.**

  Pre-1.0 with no real users, so both are hard cuts rather than dual-format transitions.
- `0.7.0` adds `encrypchat_node_set_blocked_tokens` and error code `12` (`PeerBlocked`). Additive, so
  an older client keeps working against a newer core; a client that calls the new symbol must require
  `>= 0.7.0`, otherwise the symbol lookup fails at load time instead of reporting a version mismatch.
- The Flutter client enforces that floor itself: `EncrypchatCore.open()` reads `api_version` before
  looking up any other symbol and throws `CoreVersionException` ("rebuild with `make build-ffi`") when
  the library on disk is older.

## Types

| Logical type | Representation | Notes |
| --- | --- | --- |
| Secret key | `uint8[32]` | X25519 static secret; store only in OS secure storage / encrypted DB |
| Public key | `uint8[32]` | X25519 public, **canonically encoded**: bit 255 clear and the little-endian value below `2^255 - 19`. Anything else is an alias of the same key and returns `InvalidPublicKey` (2) |
| Token | UTF-8 string | `ec_` + 64 hex chars (SHA-256 of public key); buffer ≥ 68 bytes incl. NUL |
| `db_key` | `uint8[32]` | Local AEAD key (secure storage); seals message bodies at rest |
| Plaintext | `uint8[]` | Never sent to network unencrypted |
| Network ciphertext | `uint8[]` | `eph_pub(32) \|\| nonce(12) \|\| chacha20poly1305` with AAD `encrypchat-msg-v1` |
| Sealed blob (relay) | `uint8[]` | `ECS1` — see [Sealed sender](#sealed-sender-relay-payloads-080); 136 bytes of overhead |
| `msg_id` | `uint8[16]` | Random per sealed blob; the recipient's de-duplication key |
| Local sealed | `uint8[]` | `nonce(12) \|\| chacha20poly1305` with AAD `encrypchat-local-v1` |
| Wire frame | `uint8[]` | See [phase-4.md](phase-4.md) (`EC04` framing) |
| Node handle | opaque pointer | From `encrypchat_node_start`; free with `encrypchat_node_stop` |

## C ABI (Phases 4–5)

All functions return `0` on success, non-zero `CoreError` code on failure (except `try_recv`, which returns `9` when empty).
Caller owns returned buffers and must free with `encrypchat_free`.

Byte-slice parameters (`plaintext`, `ciphertext`, `sealed`, `frame`, `nonce`) accept `NULL` when their
length is `0` and treat it as an empty slice; the length is what decides. Handles are declared `void *`
here but exported as `*mut NodeHandle` in Rust — ABI-identical, and callers must keep treating them as
opaque.

```c
// version
int encrypchat_api_version(char *out, size_t cap); // writes "0.8.1"

// identity
int encrypchat_identity_generate(uint8_t out_secret[32], char *out_token, size_t token_cap);
int encrypchat_identity_token(const uint8_t secret[32], char *out_token, size_t token_cap);
int encrypchat_identity_public_key(const uint8_t secret[32], uint8_t out_pub[32]);

// e2ee (network)
int encrypchat_encrypt(
  const uint8_t recipient_pub[32],
  const uint8_t *plaintext, size_t plaintext_len,
  uint8_t **out_ciphertext, size_t *out_len
);
int encrypchat_decrypt(
  const uint8_t secret[32],
  const uint8_t *ciphertext, size_t ciphertext_len,
  uint8_t **out_plaintext, size_t *out_len
);

// local at-rest AEAD (db_key)
int encrypchat_local_seal(
  const uint8_t key[32],
  const uint8_t *plaintext, size_t plaintext_len,
  uint8_t **out, size_t *out_len
);
int encrypchat_local_open(
  const uint8_t key[32],
  const uint8_t *sealed, size_t sealed_len,
  uint8_t **out, size_t *out_len
);

// P2P node
int encrypchat_node_start(const uint8_t secret[32], uint16_t listen_port, void **out_handle);
void encrypchat_node_stop(void *handle);
int encrypchat_node_local_token(void *handle, char *out_token, size_t cap);
int encrypchat_node_send(void *handle, const char *token, const uint8_t *frame, size_t frame_len);
int encrypchat_node_try_recv(void *handle, uint8_t **out, size_t *out_len); // 0=msg, 9=empty
int encrypchat_node_peer_count(void *handle, size_t *out_count);
int encrypchat_node_listen_addr(void *handle, char *out, size_t cap); // e.g. /ip4/127.0.0.1/tcp/PORT
int encrypchat_node_connect(void *handle, const char *multiaddr);     // dial; EH02 proves the peer token

// blocklist (0.7.0) — replaces the whole set; count == 0 clears it (tokens may be NULL)
int encrypchat_node_set_blocked_tokens(void *handle, const char *const *tokens, size_t count);

// sealed sender (0.8.0) — relay payloads; sender bound to content, verified by recipient only
int encrypchat_sealed_seal(
  const uint8_t sender_secret[32],
  const uint8_t recipient_pub[32],
  const uint8_t *plaintext, size_t plaintext_len,
  uint8_t **out_blob, size_t *out_len,
  uint8_t out_msg_id[16],
  uint64_t *out_sent_at
);
int encrypchat_sealed_open(
  const uint8_t recipient_secret[32],
  const uint8_t *blob, size_t blob_len,
  uint64_t now_unix_secs,          // 0 disables the freshness window
  uint8_t out_sender_pub[32],
  char *out_sender_token, size_t token_cap,
  uint8_t out_msg_id[16],
  uint64_t *out_sent_at_unix,
  uint8_t **out_plaintext, size_t *out_len
);

// relay PoP (Phase 5) — proof[32] = SHA-256(domain || ECDH(secret, eph_pub) || nonce || token)
int encrypchat_pop_proof(
  const uint8_t secret[32],
  const uint8_t eph_pub[32],
  const uint8_t *nonce, size_t nonce_len,
  const char *token_cstr,
  uint8_t out_proof[32]
);

void encrypchat_free(void *ptr);
```

## Invariants for FFI callers

1. Never log `secret` / `db_key` bytes or pass them to analytics. The core wipes the copies it owns
   (staging buffers, and the node's session-long copy when `node_stop` runs), but buffers you allocate
   are yours to zeroize — and so is the buffer the core hands back, because `encrypchat_free` is a
   plain free. The Dart bridge does both: every staging buffer that held a key or a plaintext is
   wiped before `calloc.free`, and every out-buffer is wiped after being copied out. What it cannot
   reach is the `Uint8List` on the GC heap, which is why a decrypt taking a node handle instead of
   32 bytes would be strictly better (F-10 in [audit-f10.md](audit-f10.md)).
2. `Debug` of Rust `Identity` redacts secrets; keep that property in Dart (`toString` must not print keys).
3. Token is the only stable contact identifier exposed in UI.
4. Empty plaintext is rejected (encrypt and local_seal).
5. Network payloads must already be E2EE ciphertext (from `encrypt`) before `node_send`.
6. Local DB message bodies must be sealed with `local_seal` (`db_key`), not plaintext.
7. Peer unknown/offline → `PeerOffline` (8); no relay in Phase 4.
8. Null checks return `NullPointer` (7); undersized buffers return `BufferTooSmall` (6). Both are clean
   failures: on any error no out-parameter is written, so `identity_generate` never leaves key material
   in `out_secret` when the token buffer is too small (< 68 bytes).
9. Entry points catch panics and map them to `Internal` (255).
10. `pop_proof` with an empty nonce fails `AuthFailed` (11), not `NullPointer` (7): a proof over no
    challenge is worthless regardless of whether the caller passed `NULL` or a zero-length buffer.
11. The core blocklist is a second line of defence, not a replacement for the client's own filtering:
    it starts empty on every `node_start`, so the caller must push the persisted set after start.
12. Relay payloads must be sealed with `encrypchat_sealed_seal`, never with `encrypchat_encrypt`, and
    must not carry a `from` field: the sender is whatever `encrypchat_sealed_open` returns, or the blob
    is dropped. `AuthFailed` (11) is a forgery, not a decode hiccup.
13. Sealed blobs are not replay-proof. The caller must remember `msg_id` for at least the freshness
    window (7 days + skew) and drop repeats.
14. A public key is one key with one encoding (`0.8.1`). Pass the 32 bytes exactly as the core
    produced them; never normalise, mask or re-encode a key on the Dart side, and treat
    `InvalidPublicKey` (2) on an imported key or a scanned QR as "this contact card is malformed",
    not as a transient failure. The token is only a stable identity because the encoding is fixed:
    if a caller ever accepted an alias itself, it would be handing the same peer two identities and
    a way around a block.

## Blocking budgets and limits

The node entry points are synchronous and talk to the embedded Tokio runtime, so they can block the
calling (UI) thread. Call them off the Flutter main isolate. The Dart client does that for `send`,
`connect` and `stop` through a worker isolate (`apps/client/lib/core/core_worker.dart`): the library
is loaded again there, the node handle travels as an address rather than a pointer, and `stop` is
queued behind the sends so the handle is never freed with a call inside it. `try_recv`,
`peer_count`, `start` and everything under a millisecond stay on the main isolate.

| Call | Budget | On expiry |
| --- | --- | --- |
| `encrypchat_node_start` | 5 s to bind the TCP listener | `Internal` (255) |
| `encrypchat_node_send` | 15 s waiting for the peer ACK | `PeerOffline` (8) |
| `encrypchat_node_connect` | 10 s to dial + finish the EH02 handshake | `Internal` (255) |
| `encrypchat_node_peer_count` | 2 s querying the command loop | `Internal` (255), `out_count` untouched |
| `encrypchat_node_try_recv` | none — non-blocking poll | `Empty` (9) |

`peer_count` never reports a failure as a count: a timeout or a dead command loop returns `Internal`
(255) and leaves `out_count` alone, so a written `0` always means "no peers are known".

Frame size: `encrypchat_node_send` rejects payloads above **16 MiB** (`MAX_FRAME_LEN`) with
`InvalidFrame` (10) — the limit is on the frame the caller passes, before the transport wraps it. On the
wire each record adds 21 bytes and anything below 512 bytes of plaintext is padded up to it, so short
messages and ACKs all cost 532 bytes. Media above the limit must be chunked by the caller. Pre-authentication reads are capped
much lower (4 KiB) and the EH02 handshake has its own 5 s budget, so an unauthenticated peer cannot pin
memory. Once authenticated, a peer *can* pin memory: the inbound queue is bounded by message count, not
bytes (F-9 in [audit-f10.md](audit-f10.md)).

## Blocklist — `encrypchat_node_set_blocked_tokens`

```c
int encrypchat_node_set_blocked_tokens(void *handle, const char *const *tokens, size_t count);
```

Replaces the node's blocked-token set. Defence in depth behind the client's own block list, which
already drops inbound frames before decrypting and withholds sends; the core layer exists so a blocked
peer cannot hold a P2P session and consume node resources.

| Aspect | Semantics |
| --- | --- |
| Representation | Array of `count` C strings, not one delimited string: no delimiter to escape, no ambiguity between "empty list" and "list with one empty entry", and the count is explicit |
| Replace vs accumulate | **Replace.** The whole set is swapped, so the caller keeps a single source of truth and rewrites it on every change; there is no add/remove |
| Empty list | `count == 0` clears the set. `tokens` may be `NULL` in that case |
| Normalisation | The core trims and lowercases every entry (same rule as `Token::parse`), so mixed-case hex is not a bypass. Sends are normalised before the lookup too |
| Validation | Malformed entry (bad prefix, wrong length, non-hex, non-UTF-8) → `InvalidToken` (1), previous set kept. Never partially applied |
| Null handling | `handle` null, `tokens` null with `count != 0`, or any null entry → `NullPointer` (7), previous set kept |
| Lifetime | Entries are copied into owned Rust strings before returning; free the array and strings right after the call |
| Threading | Callable from any thread while the node runs, concurrently with other `encrypchat_node_*` calls |
| Lifecycle | Not persisted and not inherited: every `node_start` begins with an empty set |

Effect of a token being on the list:

| Path | Behaviour |
| --- | --- |
| Inbound or outbound session setup | Refused once the peer is authenticated → `PeerBlocked` (12) to the local caller on `node_connect`; a remote dialer just sees the socket close |
| Session already open when the block lands | Closed on the peer's next frame; the frame is dropped un-ACKed and never reaches `try_recv` |
| `encrypchat_node_send` | `PeerBlocked` (12) before anything is queued |
| Idle open session | Stays open until its next frame or a normal disconnect. It can neither deliver nor receive, but the socket is not torn down proactively |

### Cost: a blocked peer still pays for a handshake

Rejection happens **after** the peer has proved its identity, not before, and that is deliberate: the
only trustworthy sender token is one the peer has proved possession of. Filtering on a token declared
before the proof would mean filtering on a value the attacker picks. The consequence is inherent and
not hidden: a blocked peer can still open a TCP connection and run a handshake against the node (a
handful of X25519 operations plus the framing), and only then is refused. The existing pre-auth limits
are what bound the abuse — a 4 KiB cap on pre-auth reads, a 5 s handshake budget, and the in-flight
handshake semaphore — so a blocked peer costs no more than any unauthenticated stranger.

On the accepting side the refusal lands between EH02 messages 3 and 4, so a blocked peer pays for the
handshake without learning the local identity.

## Sealed sender (relay payloads, 0.8.0)

A relay blob has no session behind it: until `0.8.0` the sender was a `from` string *declared*
inside the ciphertext, so anyone holding the recipient's public key could encrypt a blob and
claim to be one of their contacts. `ECS1` closes that.

An earlier revision of this section said the P2P path was already safe because EH01
authenticated the peer. It did not — see F-1 in [audit-f10.md](audit-f10.md) — and the same
`0.8.0` cut replaces that handshake with EH02, which uses this same double-DH construction.

Identities are X25519 and cannot sign, so the sender is authenticated with a second
Diffie-Hellman instead — the Noise `X` pattern:

| DH | Inputs | Buys |
| --- | --- | --- |
| `es` | ephemeral × recipient static | Confidentiality, and sender anonymity towards the relay |
| `ss` | sender static × recipient static | Proof that the holder of the sender's secret produced this blob |

Only the recipient can check `ss`, so a blob is **not** transferable proof of authorship:
anyone with the recipient's secret could have produced it. That deniability is intended — a
public signature would turn every relayed blob into a receipt of who wrote to whom.

### Wire format

```text
magic(4)             "ECS1"
eph_pub(32)          X25519 ephemeral, fresh per blob
nonce(12)            random; both AEAD layers use it under different keys
sealed_sender(48)    ChaCha20-Poly1305(k_id)  over sender_pub(32)
body(24 + n + 16)    ChaCha20-Poly1305(k_msg) over msg_id(16) || sent_at(8, big-endian) || payload(n)

k_id  = SHA-256("encrypchat-sealed-id-v1"  || es       || E || R)
k_msg = SHA-256("encrypchat-sealed-msg-v1" || es || ss || E || R || S)
```

`S` = sender public, `R` = recipient public, `E` = ephemeral public; every hashed input is a
fixed 32-byte value, so concatenation is unambiguous. Overhead is 136 bytes, and the 256 KiB
relay `MAX_BLOB_BYTES` applies to the sealed blob.

The payload key commits to `S`, so the sender is bound to the *content*: there is no field to
strip, and a `sealed_sender` spliced from another blob yields a key nobody can reproduce.
Small-order peer keys are rejected (`InvalidPublicKey` (2) on seal), since their shared secret
is all-zero and would be computable by a stranger.

Binding to `S` binds to the *bytes* of `S`, which is why `0.8.1` also rejects a non-canonical
`S` on open. An alias of the sender's own key produces an equally valid blob — `ss` does not
change — and would have been reported as an authenticated sender under a different token.

### `encrypchat_sealed_seal`

| Aspect | Semantics |
| --- | --- |
| Use for | Anything enqueued on a relay — text, media, and (once the client allows it) call signaling |
| Do **not** use for | The P2P path: `EC04` frames keep `encrypchat_encrypt`, whose sender is already the authenticated session token |
| `out_blob` | `malloc`ed, `136 + plaintext_len` bytes, freed with exactly one `encrypchat_free` |
| `out_msg_id` | The 16 random bytes bound inside the blob; the peer sees the same value |
| `out_sent_at` | The Unix timestamp bound inside the blob, read from the core's clock so it cannot drift from what the peer verifies |
| Payload | Must no longer carry a `from` field. Attribution comes from `encrypchat_sealed_open` |
| Errors | `EmptyPlaintext` (5), `InvalidPublicKey` (2) on a degenerate **or non-canonically encoded** recipient key, `NullPointer` (7) |

### `encrypchat_sealed_open`

| Aspect | Semantics |
| --- | --- |
| `out_sender_pub` / `out_sender_token` | The **authenticated** sender. `token_cap` ≥ 68. Use these, never a value from the payload |
| `out_msg_id` / `out_sent_at_unix` | For de-duplication and display; `sent_at` is authenticated but sender-chosen, so treat it as a claim, not as a trusted clock |
| `now_unix_secs` | Wall clock in seconds. `0` disables the freshness window (tests, or a device with no trustworthy clock) |
| Freshness window | `sent_at` more than 300 s in the future or more than 7 days (the relay's max TTL) in the past → `Expired` (13), checked *after* authentication |
| All-or-nothing | On any error no out-slot is written. A too-small `token_cap` releases the internal plaintext allocation before returning `BufferTooSmall` (6) |

Error mapping is deliberately split so the caller can react correctly:

| Code | Meaning | Caller should |
| --- | --- | --- |
| `InvalidFrame` (10) | Not an `ECS1` blob (e.g. a pre-0.8.0 payload) | Drop it. There is no legacy path to fall back to |
| `CiphertextTooShort` (4) | `ECS1` but truncated (minimum is 137 bytes) | Drop it |
| `DecryptionFailed` (3) | Not addressed to this identity, or the header is corrupt | Drop it |
| `InvalidPublicKey` (2) | Addressed to us, but the sender key is a non-canonical encoding — an alias trying to earn a second token (F-10) | Drop it. Do not "fix" the encoding and retry |
| `AuthFailed` (11) | Addressed to us, but the sender binding does not hold — forged sender or tampered body | Drop it. **Never** fall back to a declared sender |
| `Expired` (13) | Authentic, but outside the freshness window | Drop it, optionally warn about clock skew |

### What this does not solve: replay

A captured blob replays byte-for-byte and opens again. This is the caller's problem to close
and the core gives it exactly what it needs:

- The blob is bound to **one destination** (`R` is in both keys), so it cannot be re-aimed at
  another mailbox, and to **one sender**, so it cannot be re-attributed.
- `msg_id` is stable across replays, so a seen-id set is enough to drop duplicates.
- The freshness window bounds how long that set has to live: ids older than 7 days plus the
  skew can be forgotten, because such a blob is rejected anyway.

The Flutter client keeps that set in its local database (`seen_sealed`, schema v5) and prunes it
with the window — see *Anti-replay* in [audit-f10.md](audit-f10.md). Without such a set a relayed
message can be duplicated by anyone who captured the blob (it stays in flight only until the
recipient pulls it, since pull deletes). It can never be forged, altered, or re-addressed.

### What the relay learns: nothing new

The relay sees magic, a fresh ephemeral public key, a random nonce, and two ciphertexts. The
sender's key and token appear nowhere in the clear; `sealed_sender` is encrypted under a key
derived from a per-blob ephemeral, so it is indistinguishable from random and two blobs from
the same sender to the same recipient share no bytes. Compared with the previous format the
relay only sees 52 more opaque bytes. No relay code changed.

## Known gap: `try_recv` under allocation failure

`try_recv` pops the frame off the inbound queue before allocating the buffer it hands back, so if that
allocation fails the frame is gone and the caller only sees `Internal` (255). The sender has already
received its `MSG_ACK` by then — the node withholds the ACK when the inbound queue is full, but not for
this later failure — so it treats the message as delivered and never retries.

Only an out-of-memory condition triggers this, which on all four targets means the process is already
being reclaimed, so the queue is deliberately left as-is rather than growing a push-back path. Callers
should still treat `255` from `try_recv` as possible silent message loss, not as a transient poll error.

## Error codes

| Code | Meaning |
| --- | --- |
| 1 | InvalidToken |
| 2 | InvalidPublicKey (degenerate, or a non-canonical encoding of a valid key) |
| 3 | DecryptionFailed |
| 4 | CiphertextTooShort |
| 5 | EmptyPlaintext |
| 6 | BufferTooSmall |
| 7 | NullPointer |
| 8 | PeerOffline |
| 9 | Empty (try_recv would-block) |
| 10 | InvalidFrame |
| 11 | AuthFailed |
| 12 | PeerBlocked (token is on the local blocklist) |
| 13 | Expired (sealed blob outside the freshness window) |
| 255 | Internal |

## Out of scope (later phases)

- Relay envelope (`destination_token` + TTL + blob)
- Media chunking
- Full LAN mDNS discovery (manual `inject_peer` / `connect_multiaddr` for now)
- SQLCipher page encryption (bodies use local AEAD)
