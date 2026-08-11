# FFI contract — Encrypchat core ↔ Flutter

Status: Phase 2 design (no native bridge wired yet; Phase 3 implements).

## Versioning

- Rust crate: `encrypchat_core` `api_version()` → `0.2.0`
- Bump `api_version` whenever exported FFI signatures or wire formats change.

## Types

| Logical type | Representation | Notes |
| --- | --- | --- |
| Secret key | `uint8[32]` | X25519 static secret; store only in OS secure storage / encrypted DB |
| Public key | `uint8[32]` | X25519 public |
| Token | UTF-8 string | `ec_` + 64 hex chars (SHA-256 of public key) |
| Plaintext | `uint8[]` | Never sent to network unencrypted |
| Ciphertext | `uint8[]` | `eph_pub(32) \|\| nonce(12) \|\| chacha20poly1305(ciphertext\|\|tag)` |

## Suggested C ABI (Phase 3)

All functions return `0` on success, non-zero `CoreError` code on failure.
Caller owns returned buffers and must free with `encrypchat_free`.

```c
// identity
int encrypchat_identity_generate(uint8_t out_secret[32], char *out_token, size_t token_cap);
int encrypchat_identity_token(const uint8_t secret[32], char *out_token, size_t token_cap);
int encrypchat_identity_public_key(const uint8_t secret[32], uint8_t out_pub[32]);

// e2ee
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

void encrypchat_free(void *ptr);
```

## Invariants for FFI callers

1. Never log `secret` bytes or pass them to analytics.
2. `Debug` of Rust `Identity` redacts secrets; keep that property in Dart (`toString` must not print keys).
3. Token is the only stable contact identifier exposed in UI.
4. Empty plaintext is rejected.

## Error codes (draft)

| Code | Meaning |
| --- | --- |
| 1 | InvalidToken |
| 2 | InvalidPublicKey |
| 3 | DecryptionFailed |
| 4 | CiphertextTooShort |
| 5 | EmptyPlaintext |
| 255 | Internal |

## Out of scope (later phases)

- libp2p transport framing
- Relay envelope (`destination_token` + TTL + blob)
- Media chunking
