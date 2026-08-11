# encrypchat_relay

Blind relay stub for Encrypchat.

## Role (Phase 5+)

- Accept **ciphertext** + destination **token** + **TTL**
- Serve pull authenticated by proof of key possession
- Delete after delivery
- **Never** see plaintext chats or private keys

## Phase 0

Binary compiles and prints a stub message. No network listener yet.

```bash
cargo run -p encrypchat_relay
```
