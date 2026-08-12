# encrypchat_relay

Blind HTTP mailbox for Encrypchat (Phase 5). Stores **opaque ciphertext** only.

## What the relay sees

| Visible | Not visible |
| --- | --- |
| Destination token (`ec_` + 64 hex) | Message plaintext |
| Blob size (bytes) | Private keys / identity secrets |
| Enqueue / pull timing | Decrypted content of any kind |
| Message id (UUID) | Contact lists or phone numbers |

The relay **never decrypts**. Blobs are ciphertext produced by the client (`encrypt` in `encrypchat_core`) before enqueue.

## Run

```bash
# defaults: 0.0.0.0:8787, ./data/relay.sqlite
cargo run -p encrypchat_relay

ENCRYPCHAT_RELAY_ADDR=127.0.0.1:8787 \
ENCRYPCHAT_RELAY_DB=/var/lib/encrypchat/relay.sqlite \
cargo run -p encrypchat_relay
```

### Env

| Variable | Default | Meaning |
| --- | --- | --- |
| `ENCRYPCHAT_RELAY_ADDR` | `0.0.0.0:8787` | Listen address |
| `ENCRYPCHAT_RELAY_DB` | `./data/relay.sqlite` | SQLite path |
| `RUST_LOG` | `info` | Tracing filter |
| `ENCRYPCHAT_RELAY_MAX_MSGS` | `200` | Pending blobs per destination token |
| `ENCRYPCHAT_RELAY_MAX_BYTES` | `8388608` | Pending bytes per destination token (8 MiB) |
| `ENCRYPCHAT_RELAY_ENQUEUE_RPM` | `60` | `enqueue` requests per minute, per client IP |
| `ENCRYPCHAT_RELAY_CHALLENGE_RPM` | `30` | `challenge` (and `pull`) requests per minute, per client IP |

Unparseable values fall back to the default and log a warning.

## Abuse limits

### Per-destination quota

`enqueue` counts the non-expired blobs already queued for the destination — under the
same lock as the insert, so concurrent writers cannot both slip past the ceiling — and
rejects with `507 Insufficient Storage` when the new blob would exceed either the message
or the byte limit. Pulling (which deletes) frees the quota again.

The response is deliberately opaque (`destination mailbox unavailable`): no counts, no
limits, and the same text for both ceilings. Anyone can enqueue to any token by design,
so a detailed error would turn `enqueue` into a mailbox-state oracle. **Residual leak,
stated honestly:** a third party who enqueues one blob and gets `507` learns the box was
already near full. Closing that needs sender authentication (F5 P0), not a better message.

### Per-IP rate limit

In-memory token bucket per client IP, burstable up to the per-minute budget: `enqueue`,
`challenge` and `pull` each have their own bucket. Over budget → `429 Too Many Requests`
(no `Retry-After` header yet; clients back off on their own poll interval). `/healthz` is
not limited.

Limits are per process and per IP, so they bound a direct flood, not a distributed one.
Behind a reverse proxy every request arrives with the proxy's address: `X-Forwarded-For`
is spoofable and is deliberately not trusted, so the proxy must do its own limiting.
A poisoned limiter lock fails open — availability over strictness.

## API

### `POST /v1/enqueue`

```json
{ "dest_token": "ec_…", "ttl_secs": 86400, "blob_b64": "…" }
→ { "id": "uuid" }
```

- Token: `ec_` + 64 hex
- Max blob: 256 KiB
- Max TTL: 7 days (clamped)
- `429` over the per-IP rate limit · `507` when the destination quota is full

### `POST /v1/challenge`

```json
{ "dest_token": "ec_…" }
→ { "nonce_b64": "…", "eph_pubkey_b64": "…" }
```

Creates a short-lived (2 min) one-shot PoP challenge (relay ephemeral X25519 + nonce).

### `POST /v1/pull`

```json
{ "dest_token": "ec_…", "pubkey_b64": "…", "proof_b64": "…" }
→ { "messages": [ { "id": "…", "blob_b64": "…" } ] }
```

Proof-of-possession (ECDH):

1. Client: `proof = SHA-256("encrypchat-pop-v1" ‖ ECDH(secret, eph_pub) ‖ nonce ‖ token)`
2. Relay: same with `ECDH(eph_secret, client_pub)`, constant-time compare
3. On success: return all non-expired blobs for the token, then **delete** them

Helpers: `encrypchat_core::pop_proof` / `pop_verify`, FFI `encrypchat_pop_proof`.

### `GET /healthz`

`200` if process is up.

## Storage

SQLite tables:

- `mailbox(id, dest_token, blob, expires_at, created_at)`
- `challenges(dest_token, eph_secret, eph_pub, nonce, expires_at)`

Expired rows purged on request and every 60s in the background.

## Tests

```bash
cargo test -p encrypchat_relay
cargo test -p encrypchat_core
```

## Log policy

The relay must not retain "who receives and when". Application logs carry:

| Logged | Never logged |
| --- | --- |
| Message id (UUID), blob size, TTL | `dest_token` (full or truncated) |
| Pull result count | Pubkeys, proofs, nonces, blob bytes |

`dest_token` is needed in memory to route and to verify PoP, but it is not written to
logs — a token prefix is still a stable identifier and would rebuild the delivery graph.

Operators: keep `RUST_LOG` at `info` or lower verbosity, do not enable request-body
logging in a reverse proxy, and disable access logs that record request payloads.
Access logs with client IPs are outside the relay; treat them as retained metadata.

## Ops notes

- CORS is permissive for local demos; Flutter clients typically hit a LAN IP (no browser CORS).
- Do not put this process on a path that logs request bodies (blobs are still ciphertext, but size/timing are metadata).
- Rotate or wipe `ENCRYPCHAT_RELAY_DB` if compromised — only undelivered ciphertext is lost, not identity keys.
