# Auditor review — Phase 6 media (photos E2EE)

Readonly audit (2026-08-12). Scope: `media_envelope.dart`, `media_store.dart`,
`messaging_service.dart` (send/receive media), `chat_page.dart` attach UI,
`docs/phase-6.md`.

**Verdict:** PASS WITH NOTES — OK for LAN/demo. Not production-hardened.

## Holds

- Media E2EE at origin (`encrypt` before P2P frame / relay enqueue)
- At-rest: `local_seal` under app-support `media/<id>.bin`; no plaintext bytes in DB
- Relay: client fail-loud at 256 KiB + server `MAX_BLOB_BYTES`
- Path traversal on write: `_safeId` + `isWithin(media/)`

## Findings

| Sev | Item |
| --- | --- |
| ~~High~~ | ~~Relay media JSON `from` unauthenticated (same class as F5 text)~~ — core fix landed (`ECS1` sealed sender, `api_version` `0.8.0`); pending the client wiring, same as F5 |
| Medium | Inbound EM01 size — capped in decode (post-audit fix) |
| Low | `looksLike` magic-only; decode fail drops frame |
| Low | Gallery picker temps not explicitly wiped |
| Low | `readSealed` should require `media/<safeId>.bin`, not only `isWithin` |

## Watch

| Item | Note |
| --- | --- |
| RAM cache | Full image in `mediaBytes` while chat open |
| EM01 encoding | `codeUnits` ≠ UTF-8; document or fix before cross-lang |
| Mime trust | No magic-byte check vs declared mime |

## P0 before production

1. ~~Bind/sign sender on relay media (and text) payloads~~ — core side done; media blobs
   must go through `encrypchat_sealed_seal` like text ([audit-f5-relay.md](audit-f5-relay.md))
2. Carry F5 public-relay P0s (TLS, challenge rate-limit)

## Demo vs release

- Demo/LAN: acceptable
- Public release: blocked on P0 #1 + F5 hardening
