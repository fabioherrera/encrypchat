# encrypchat_core

Local identity, E2EE, at-rest AEAD, and P2P text transport for Encrypchat.

## Phase 4 / 0.5.0 (EH01)

| Area | API |
| --- | --- |
| Identity / E2EE | `Identity`, `encrypt` / `decrypt` (AAD `encrypchat-msg-v1`) |
| Local at-rest | `seal_local` / `open_local` with 32-byte `db_key` |
| Wire frame | `WireFrame` / `encode_frame` / `decode_frame` (`EC04`) |
| Networking | `NodeHandle` — Tokio TCP, **EH01** auth hello, length-prefixed data+ack |
| FFI | C ABI in `src/ffi.rs`, `api_version` → `0.5.0` |

```bash
cargo test -p encrypchat_core
cargo build -p encrypchat_core --release
# → target/release/libencrypchat_core.so (and .a / rlib)
```

Transport notes: [docs/phase-4.md](../../docs/phase-4.md)  
Contract: [docs/ffi-contract.md](../../docs/ffi-contract.md)
