# FFI contract — Encrypchat core ↔ Flutter

Status: **Phase 4 + EH01 auth hello** (`crates/core` C ABI + `api_version` `0.5.0`).

## Versioning

- Rust crate: `encrypchat_core` `api_version()` → `0.5.0`
- Bump `api_version` whenever exported FFI signatures or wire formats change.

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

## C ABI (Phase 4)

All functions return `0` on success, non-zero `CoreError` code on failure (except `try_recv`, which returns `9` when empty).
Caller owns returned buffers and must free with `encrypchat_free`.

```c
// version
int encrypchat_api_version(char *out, size_t cap); // writes "0.5.0"

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

void encrypchat_free(void *ptr);
```

## Invariants for FFI callers

1. Never log `secret` / `db_key` bytes or pass them to analytics.
2. `Debug` of Rust `Identity` redacts secrets; keep that property in Dart (`toString` must not print keys).
3. Token is the only stable contact identifier exposed in UI.
4. Empty plaintext is rejected (encrypt and local_seal).
5. Network payloads must already be E2EE ciphertext (from `encrypt`) before `node_send`.
6. Local DB message bodies must be sealed with `local_seal` (`db_key`), not plaintext.
7. Peer unknown/offline → `PeerOffline` (8); no relay in Phase 4.
8. Null checks return `NullPointer` (7); undersized buffers return `BufferTooSmall` (6).
9. Entry points catch panics and map them to `Internal` (255).

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
| 255 | Internal |

## Out of scope (later phases)

- Relay envelope (`destination_token` + TTL + blob)
- Media chunking
- Full LAN mDNS discovery (manual `inject_peer` / `connect_multiaddr` for now)
- SQLCipher page encryption (bodies use local AEAD)
