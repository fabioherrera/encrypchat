# Encrypchat Flutter client

Multiplataforma: Android, iOS, Linux (Fedora), Windows.

## Fase 3

Shell con onboarding, token/QR, contactos (import/export) y lista de chats vacía.
Crypto vía FFI a `encrypchat_core` (`make build-ffi`).

```bash
# desde la raíz del monorepo
make build-ffi
make dev-client          # Linux
cd apps/client && flutter test
```

Detalles y gaps: [docs/phase-3.md](../../docs/phase-3.md).
