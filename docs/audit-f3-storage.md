# Auditor review — Phase 3 key/storage

Readonly review of F3 identity + local storage + FFI (2026-08-12).

**Verdict:** pass-with-notes (OK for F3 identity shell; **not** OK to persist message plaintext under current DB model).

## Findings (post-remediation notes)

| Sev | Item | Status after F3 close |
| --- | --- | --- |
| Medium | Unused `db_key` / plaintext SQLite | **Closed in F10** — see below |
| Medium | Android Auto Backup of DB | **Mitigated** (`allowBackup="false"`) |
| Low | FFI buffers not zeroized before free | **Closed in F10** — every native buffer that held a key or a plaintext is wiped before it is freed, in both directions (F-10 in [audit-f10.md](audit-f10.md)). The Dart-heap copies are out of the language's reach |
| Low | Raw key fingerprint | **Fixed** (SHA-256 tag) |
| Low | Secure-storage platform options thin | Open — F8 parity |

## Follow-ups before F4 message persistence

1. ~~Wire SQLCipher `PRAGMA key` (or AEAD bodies) using `db_key`.~~ **Done** — AEAD bodies in F4, file encryption in F10 (below).
2. ~~Zeroize secrets across Dart/Rust FFI free paths.~~ **Done in F10** — what remains is the GC heap, which needs the key to stop crossing the boundary.
3. AEAD AAD (carryover F2).
4. Re-run `/auditor` after at-rest crypto lands.

Full narrative: agent transcript auditor pass (2026-08-12).

## F10 — file encryption landed (2026-08-12)

The database file is a **SQLCipher 4.17 (community)** database now: AES-256-CBC
pages with per-page HMAC, salt in the file header. It is not a SQLite file any
more — `sqlite3 encrypchat_v1.db "select * from contacts"` answers
`file is not a database (26)`, and the same goes for Python's `sqlite3`.

### How

| Piece | Decision |
| --- | --- |
| Library | `package:sqlite3` hook, `source: sqlcipher` (`apps/client/pubspec.yaml`) — prebuilt SQLCipher for Android, iOS, Linux, Windows; **replaces** the bundled `libsqlite3`, so the process never holds two SQLite copies |
| Access layer | `sqflite_common_ffi` on all four platforms. The `sqflite` native plugin was dropped: on Android/iOS it talks to the OS SQLite, which cannot open an encrypted file |
| File key | `HMAC-SHA256(db_key, "encrypchat/sqlcipher/file-key/v1")`, passed as a raw key (`PRAGMA key = "x'…'"`, no PBKDF2 — `db_key` is already 256 bits of entropy from the OS secure store) |
| Bodies | Unchanged: still sealed with `local_seal(db_key, …)`. Two layers, two keys, one stored secret; nothing had to be re-sealed |

### Migrating an existing plaintext database

SQLCipher cannot key a plaintext file, so `LocalDatabase.open()` converts it
before touching it. The plaintext file is never the thing being modified:

1. `sqlcipher_export` into `encrypchat_v1.db.encrypting`, copying `user_version`
   too (losing it would re-run the schema migrations).
2. Verify that copy: opens with the key, `PRAGMA integrity_check` = `ok`,
   `user_version` matches, and **every table has the same row count**. Any
   mismatch deletes the copy and raises `LocalDatabaseMigrationException`; the
   plaintext database is still intact and the next launch retries.
3. Only then swap: `db → db.plaintext-backup`, `db.encrypting → db`. Both
   renames target a name that does not exist, so they are single filesystem
   operations on POSIX and on Windows alike.
4. Delete the parked plaintext copy.

Every crash window is recoverable, and recovery runs at the start of the next
`open()`:

| Died at | On disk | Recovery |
| --- | --- | --- |
| During the export | plaintext db + unverified `.encrypting` | discard the copy, convert again |
| Between the two renames | no db + `.plaintext-backup` | restore it (it is the only copy), convert again |
| Before the cleanup | encrypted db + `.plaintext-backup` | delete the parked plaintext copy |

Schema versions still work as before: a v2 file is converted first and then
upgraded v2 → v4 on the encrypted database.

### What this protects — and what it does not

Protects, for a database file read off the disk (stolen laptop, cold phone,
recovered backup, forensic image, another user account on the same machine):
peer tokens, the contact list and display names, the blocklist, message
timestamps, delivery status and `media_relpath` — the social graph that used to
be readable with the `sqlite3` CLI.

Does **not** protect:

- **A device that is unlocked with the keyring open.** The key lives in the OS
  secure store; anything that can read it (the app's own process, root, malware
  running as the user, a debugger attached to the app) can open the database.
  Full-disk encryption and the OS lock screen are still the outer boundary.
- **The `media/` directory listing.** Media *contents* are sealed with AEAD, but
  the number of files, their sizes and their timestamps are plain filesystem
  metadata.
- **Anything a relay sees.** Unchanged: `dest_token`, size, timing, IP
  ([audit-f5-relay.md](audit-f5-relay.md)).
- **A key held in memory while the app runs**, including the derived file key as
  a Dart `String` (immutable, so it cannot be zeroized like `db_key` is).
- **Losing the key.** If the secure store forgets `db_key`, the local history is
  gone. `open()` says so with `LocalDatabaseKeyException` instead of a SQLite
  error, and never starts a fresh database on top of the old one.

### Verifying

```bash
make check-client   # includes the 8 tests in local_database_cipher_test.dart
# and against a real install (app-support dir, `~/.local/share/<app>` on Linux):
sqlite3 "$(find ~/.local/share -name encrypchat_v1.db | head -1)" .tables
# expected: Error: in prepare, file is not a database (26)
```
