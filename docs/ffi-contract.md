# FFI contract — Encrypchat core ↔ Flutter

Status: **Phase 5 PoP + core blocklist** (`crates/core` C ABI + `api_version` `0.7.0`).

## Versioning

- Rust crate: `encrypchat_core` `api_version()` → `0.7.0`
- Bump `api_version` whenever exported FFI signatures or wire formats change.
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
| Public key | `uint8[32]` | X25519 public |
| Token | UTF-8 string | `ec_` + 64 hex chars (SHA-256 of public key); buffer ≥ 68 bytes incl. NUL |
| `db_key` | `uint8[32]` | Local AEAD key (secure storage); seals message bodies at rest |
| Plaintext | `uint8[]` | Never sent to network unencrypted |
| Network ciphertext | `uint8[]` | `eph_pub(32) \|\| nonce(12) \|\| chacha20poly1305` with AAD `encrypchat-msg-v1` |
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
int encrypchat_api_version(char *out, size_t cap); // writes "0.7.0"

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
int encrypchat_node_connect(void *handle, const char *multiaddr);     // dial; EH01 hello maps token

// blocklist (0.7.0) — replaces the whole set; count == 0 clears it (tokens may be NULL)
int encrypchat_node_set_blocked_tokens(void *handle, const char *const *tokens, size_t count);

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
   are yours to zeroize.
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

## Blocking budgets and limits

The node entry points are synchronous and talk to the embedded Tokio runtime, so they can block the
calling (UI) thread. Call them off the Flutter main isolate.

| Call | Budget | On expiry |
| --- | --- | --- |
| `encrypchat_node_start` | 5 s to bind the TCP listener | `Internal` (255) |
| `encrypchat_node_send` | 15 s waiting for the peer ACK | `PeerOffline` (8) |
| `encrypchat_node_connect` | 10 s to dial + finish the EH01 hello | `Internal` (255) |
| `encrypchat_node_peer_count` | 2 s querying the command loop | `Internal` (255), `out_count` untouched |
| `encrypchat_node_try_recv` | none — non-blocking poll | `Empty` (9) |

`peer_count` never reports a failure as a count: a timeout or a dead command loop returns `Internal`
(255) and leaves `out_count` alone, so a written `0` always means "no peers are known".

Frame size: `encrypchat_node_send` rejects payloads above **16 MiB** (`MAX_FRAME_LEN`) with
`InvalidFrame` (10). Media above that must be chunked by the caller. Pre-authentication reads are capped
much lower (4 KiB) and the EH01 handshake has its own 5 s budget, so an unauthenticated peer cannot pin
memory.

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
| Inbound or outbound session setup | Refused after EH01 → `PeerBlocked` (12) to the local caller on `node_connect`; a remote dialer just sees the socket close |
| Session already open when the block lands | Closed on the peer's next frame; the frame is dropped un-ACKed and never reaches `try_recv` |
| `encrypchat_node_send` | `PeerBlocked` (12) before anything is queued |
| Idle open session | Stays open until its next frame or a normal disconnect. It can neither deliver nor receive, but the socket is not torn down proactively |

### Cost: a blocked peer still pays for a handshake

Rejection happens **after** EH01 completes, not before, and that is deliberate: the only trustworthy
sender token is one the peer has proved possession of. Filtering on a token declared before the proof
would mean filtering on a value the attacker picks. The consequence is inherent and not hidden: a
blocked peer can still open a TCP connection and run a full handshake against the node (two X25519
operations plus the framing), and only then is refused. The existing pre-auth limits are what bound
the abuse — a 4 KiB cap on pre-auth reads, a 5 s handshake budget, and the in-flight handshake
semaphore — so a blocked peer costs no more than any unauthenticated stranger.

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
| 2 | InvalidPublicKey |
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
| 255 | Internal |

## Out of scope (later phases)

- Relay envelope (`destination_token` + TTL + blob)
- Media chunking
- Full LAN mDNS discovery (manual `inject_peer` / `connect_multiaddr` for now)
- SQLCipher page encryption (bodies use local AEAD)
