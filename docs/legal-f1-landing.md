# Legal review — Phase 1 landing stubs

Readonly counsel-style review of public copy on encrypchat.com pages (2026-08-11).

## Scope

Home, features, download, FAQ, privacy stub, terms stub.

## Findings

### Medium — Mailbox not live

- **Risk:** `privacy@encrypchat.com` advertised before mailbox exists.
- **Where:** `/privacy`
- **Action:** Activate mailbox before public launch, or replace with a contact form / GitHub issues note.
- **Limit:** Human ops, not code.

### Low — “Zero-cloud” must stay nuanced

- **Risk:** Users may hear “no servers at all.”
- **Where:** Home/features/FAQ already mention blind relays.
- **Action:** Keep relay nuance on every strong zero-cloud claim (currently OK). Do not add “no servers whatsoever.”
- **Limit:** SEO must not strip the nuance in titles.

### Low — Stubs labeled as stubs

- **Risk:** Stores may reject incomplete policies.
- **Where:** Privacy/Terms explicitly say Phase 9 finalize.
- **Action:** Acceptable for pre-store marketing; block store submission until Phase 9.

## Claims check

| Claim | Accurate? |
| --- | --- |
| E2EE on device | Yes (architecture) |
| Chats not in readable cloud inbox | Yes |
| Blind relay ciphertext only | Yes (intent) |
| Impossible to intercept / hack | Not claimed — good |

## Verdict

**No Critical.** Safe to publish marketing stubs with relay nuance. Activate privacy contact before wide promotion. Full ToS/Privacy = Phase 9.
