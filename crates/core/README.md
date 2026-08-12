# encrypchat_core

Local identity, E2EE, at-rest AEAD, P2P text transport, and relay PoP for Encrypchat.

## 0.8.1 (canonical public keys — one key, one token)

| Area | API |
| --- | --- |
| Identity import | `PublicIdentity::from_public_key_bytes` → **`try_from_public_key_bytes`**, now fallible |
| Everything else | Unchanged signatures; non-canonical X25519 keys are refused instead of accepted |
| FFI | No new or removed symbols; `InvalidPublicKey` (2) on inputs that used to pass, `api_version` → `0.8.1` |

**F-10 alias identities.** A token is `SHA-256` of the 32 public-key bytes, but X25519 does not
give one key one encoding: RFC 7748 masks bit 255 and reduces mod `2^255 - 19` before every
Diffie-Hellman, so `S` and `S | (1 << 255)` are the same key to the curve and two different
tokens to us. A blocked peer could set that bit on its own key and come back: the EH02 proof
and the `ECS1` sender binding both verify — the shared secrets are identical — under a token
nobody had blocked. The same held for the relay route, where `open_sealed` handed the alias to
the caller as an authenticated sender.

The fix is an encoding check at the door, and the door is the type: `Token` can only be built
from a secret this device holds (canonical by construction) or from external bytes through a
fallible constructor that rejects the aliases. There is no infallible path from arbitrary
bytes to a token, so a new entry point cannot forget the check — it will not compile without
handling the error. The wire and FFI entry points check too, so the rejection happens before
the key is used rather than at the end: `two_layer_open` (relay blobs and EH02 proofs), the
EH02 hello and challenge, `crypto::decrypt`, and the PoP pair.

Canonical is not the same as safe: the all-zero key is canonical and still degenerate. The
contributory-DH check that rejects small-order points is a separate control and both are kept.

**Compatibility.** A canonical key hashes to exactly the token it always did — pinned by a test
vector — so no identity, contact card, QR or blocklist entry changes meaning and there is no
migration. What changes is only that inputs which were previously accepted as a *second*
identity are now errors, which is why the version moves at all.

## 0.8.0 (sealed sender + EH02 handshake + encrypted P2P transport)

| Area | API |
| --- | --- |
| Relay payloads | `seal_sender` / `open_sealed` — `ECS1` blob, sender bound by static-static X25519 DH |
| P2P handshake | EH02 (internal) — same double-DH proof, mutual, responder stays anonymous until the dialer authenticates |
| P2P transport | Session key from EH02, one per direction; every record encrypted, header included |
| FFI | `encrypchat_sealed_seal`, `encrypchat_sealed_open`, `Expired` (13), `api_version` → `0.8.0` |

One construction, two holes closed. Both were the same bug: a sender that was *declared*
rather than proved.

- **Relay (F5 P0).** A blob's sender is now bound to the content and verifiable only by the
  recipient (deniable, non-transferable). Replaces the declared `from` field.
- **P2P (F-1).** EH01's proof could be built from the *verifier's* public key, so it proved
  nothing and anyone could be registered as anyone. EH02 requires the private key.

Closing those exposed a third: authenticating the peer says nothing about the wire.

- **Transport (F-15).** The `EC04` header used to travel in the clear, so an observer read the
  `sender_token` of every frame. Both ends now contribute an ephemeral to EH02, and the session
  key derived from them encrypts each record — header and kind byte included. Records below 512
  bytes are padded to it, so an ACK and a short message are the same size; above it, length
  still leaks. Forward secret **per session**, not per message: no ratchet.

**Two breaking wire formats**, both hard cuts: relay blobs, and the P2P protocol (handshake plus
transport — a `0.7.x` node and a `0.8.0` node cannot connect). No exported signature changed for
either EH02 or the transport.

Anti-replay stays with the caller on the relay path: `open_sealed` returns `msg_id` and enforces
a freshness window. On the P2P path there is a session to anchor to, so the transport handles it
itself: the AEAD nonce is an implicit per-direction counter, and a repeated or reordered record
does not decrypt.

## 0.7.0 (core blocklist)

| Area | API |
| --- | --- |
| Blocklist | `NodeHandle::set_blocked_tokens` — replaces the set, normalises tokens, hot-applied |
| FFI | `encrypchat_node_set_blocked_tokens`, `PeerBlocked` (12), `api_version` → `0.7.0` |

Refusal happens after the peer is authenticated, so a blocked peer still pays for the
handshake (but, since `0.8.0`, without learning who refused it) — see
[docs/ffi-contract.md](../../docs/ffi-contract.md).

## Phase 5 / 0.6.0 (blind relay PoP)

| Area | API |
| --- | --- |
| PoP | `pop_proof` / `pop_verify` / `pop_generate_ephemeral` (`encrypchat-pop-v1`) |
| FFI | `encrypchat_pop_proof`, `api_version` → `0.6.0` |

## Phase 4 / 0.5.0 (EH01 — superseded by EH02 in 0.8.0)

| Area | API |
| --- | --- |
| Identity / E2EE | `Identity`, `encrypt` / `decrypt` (AAD `encrypchat-msg-v1`) |
| Local at-rest | `seal_local` / `open_local` with 32-byte `db_key` |
| Wire frame | `WireFrame` / `encode_frame` / `decode_frame` (`EC04`) |
| Networking | `NodeHandle` — Tokio TCP, EH01 auth hello (**replaced**: it did not prove key possession, F-1; and it left the frames in the clear, F-15), length-prefixed data+ack |

```bash
cargo test -p encrypchat_core
cargo build -p encrypchat_core --release
# → target/release/libencrypchat_core.so (and .a / rlib)
```

Transport notes: [docs/phase-4.md](../../docs/phase-4.md)  
Relay: [docs/phase-5.md](../../docs/phase-5.md)  
Contract: [docs/ffi-contract.md](../../docs/ffi-contract.md)
