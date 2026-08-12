# encrypchat_core

Local identity, E2EE, at-rest AEAD, P2P text transport, and relay PoP for Encrypchat.

## 0.7.0 (core blocklist)

| Area | API |
| --- | --- |
| Blocklist | `NodeHandle::set_blocked_tokens` — replaces the set, normalises tokens, hot-applied |
| FFI | `encrypchat_node_set_blocked_tokens`, `PeerBlocked` (12), `api_version` → `0.7.0` |

Refusal happens after EH01, so a blocked peer still pays for the handshake — see
[docs/ffi-contract.md](../../docs/ffi-contract.md).

## Phase 5 / 0.6.0 (blind relay PoP)

| Area | API |
| --- | --- |
| PoP | `pop_proof` / `pop_verify` / `pop_generate_ephemeral` (`encrypchat-pop-v1`) |
| FFI | `encrypchat_pop_proof`, `api_version` → `0.6.0` |

## Phase 4 / 0.5.0 (EH01)

| Area | API |
| --- | --- |
| Identity / E2EE | `Identity`, `encrypt` / `decrypt` (AAD `encrypchat-msg-v1`) |
| Local at-rest | `seal_local` / `open_local` with 32-byte `db_key` |
| Wire frame | `WireFrame` / `encode_frame` / `decode_frame` (`EC04`) |
| Networking | `NodeHandle` — Tokio TCP, **EH01** auth hello, length-prefixed data+ack |

```bash
cargo test -p encrypchat_core
cargo build -p encrypchat_core --release
# → target/release/libencrypchat_core.so (and .a / rlib)
```

Transport notes: [docs/phase-4.md](../../docs/phase-4.md)  
Relay: [docs/phase-5.md](../../docs/phase-5.md)  
Contract: [docs/ffi-contract.md](../../docs/ffi-contract.md)
