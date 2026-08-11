# encrypchat_core

Local identity + E2EE for Encrypchat (no network I/O).

## Phase 2 API

- `Identity::generate` / `from_secret_bytes`
- `Identity::token` → `ec_` + hex(SHA-256(pubkey))
- `encrypt(recipient, plaintext)` / `decrypt(identity, ciphertext)`
  - Ephemeral X25519 ECDH + ChaCha20-Poly1305
  - Wire: `eph_pub(32) || nonce(12) || ciphertext||tag`

```bash
cargo test -p encrypchat_core
```

FFI design: [`docs/ffi-contract.md`](../../docs/ffi-contract.md)  
Auditor notes: [`docs/audit-f2-crypto.md`](../../docs/audit-f2-crypto.md)
