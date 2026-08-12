# Auditor review — Phase 3 key/storage

Readonly review of F3 identity + local storage + FFI (2026-08-12).

**Verdict:** pass-with-notes (OK for F3 identity shell; **not** OK to persist message plaintext under current DB model).

## Findings (post-remediation notes)

| Sev | Item | Status after F3 close |
| --- | --- | --- |
| Medium | Unused `db_key` / plaintext SQLite | **Documented** as interim pre-SQLCipher; claim wording fixed |
| Medium | Android Auto Backup of DB | **Mitigated** (`allowBackup="false"`) |
| Low | FFI buffers not zeroized before free | Open — before F4 |
| Low | Raw key fingerprint | **Fixed** (SHA-256 tag) |
| Low | Secure-storage platform options thin | Open — F8 parity |

## Follow-ups before F4 message persistence

1. Wire SQLCipher `PRAGMA key` (or AEAD bodies) using `db_key`.
2. Zeroize secrets across Dart/Rust FFI free paths.
3. AEAD AAD (carryover F2).
4. Re-run `/auditor` after at-rest crypto lands.

Full narrative: agent transcript auditor pass (2026-08-12).
