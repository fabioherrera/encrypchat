# Auditor review — Phase 2 crypto API

Readonly review of `crates/core` identity + E2EE (2026-08-11).

## Scope

- Key generation (X25519)
- Token = SHA-256(pubkey) hex with `ec_` prefix
- Encrypt/decrypt: ephemeral X25519 ECDH + ChaCha20-Poly1305
- Debug redaction of secrets

## Findings

### Medium — No authenticated associated data (AAD)

- **Where:** `crates/core/src/crypto.rs` `encrypt` / `decrypt`
- **Vector:** Ciphertext is not bound to sender identity or message type; a future MITM on transport could swap blobs between contexts if framing is weak.
- **Fix (Phase 4):** Pass AAD (e.g. protocol version + sender token + msg type) into AEAD.
- **Invariante:** E2EE confidentiality OK for Phase 2 offline API; integrity binding incomplete until transport exists.

### Low — Token is hash of pubkey only

- **Where:** `token.rs`
- **Vector:** Token does not authenticate ownership by itself (expected); QR exchange must be out-of-band trusted.
- **Fix:** Document in UX (Phase 3); optional safety numbers later.
- **Invariante:** Token identity model as designed.

### Low — `to_secret_bytes` is footgun for FFI

- **Where:** `Identity::to_secret_bytes`
- **Vector:** Callers might log or mirror bytes.
- **Fix:** Phase 3 FFI docs already forbid logging; consider `#[must_use]` wrappers / explicit `DangerousSecret` type later.

## Passes

- Private key redacted in `Debug`
- Wrong recipient cannot decrypt (test)
- Empty plaintext rejected
- No network I/O in crate
- No private keys in ciphertext layout beyond ephemeral public (expected)

## Verdict

**No Critical/High.** Phase 2 DoD acceptable with AAD deferred to Phase 4 framing. Not release-ready for network use until transport + AAD land.
