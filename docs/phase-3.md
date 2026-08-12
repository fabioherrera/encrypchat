# Fase 3 — Shell Flutter + FFI + almacenamiento local

**Estado:** done (2026-08-12) — builds Linux/Android vía F8 packaging  
**Meta:** app que arranca en Linux (Fedora) y Android, crea identidad, DB local, muestra token/QR.

## Entregado

| Pieza | Ubicación |
| --- | --- |
| C ABI FFI (`0.3.0` → actual `0.6.0`) | `crates/core/src/ffi.rs` + `docs/ffi-contract.md` |
| Dart bindings | `apps/client/lib/core/` |
| Identidad persistente | `IdentityService` + `flutter_secure_storage` |
| DB local | `LocalDatabase` (SQLite + cuerpos `body_sealed` desde F4) |
| UI | onboarding, chats, contactos (import/export), mi token + QR |
| Brand | tokens + `assets/brand/logo-mark.png` |
| Build FFI | `make build-ffi` → `apps/client/native/libencrypchat_core.so` |

## Modelo at-rest

1. **Secreto de identidad (32 bytes)** solo en OS secure storage.
2. **SQLite** en directorio privado; archivo sin `PRAGMA key` (SQLCipher aún no).
3. **Contactos / perfil:** material público (token + pubkey + nombre).
4. **Mensajes:** `body_sealed` con `local_seal(db_key)` (F4+).
5. **`db_key`** en secure storage; fingerprint = SHA-256 truncado.
6. Android: `allowBackup="false"`.

Ver [audit-f3-storage.md](audit-f3-storage.md).

## DoD

- [x] Identidad persiste tras reinicio (secure storage)
- [x] QR / export-import contacto local
- [x] Gap iOS / Windows documentado (binarios = F8)
- [x] Pases `/frontend`, `/backend`, `/auditor`
- [x] Build Linux + Android instalables — [phase-8.md](phase-8.md) / `dist/`

## Gaps de plataforma

| Target | Estado |
| --- | --- |
| Android | APK en `dist/` (`make package-android`) |
| Linux (Fedora) | Tarball en `dist/` (`make package-linux`); toolchain portable `.tools/` |
| iOS | Scaffold; sin XCFramework → gap F8 |
| Windows | Scaffold; sin `encrypchat_core.dll` → gap F8 |

## Cómo probar

```bash
make build-ffi && make check-client
make package
# o: make build-client-linux && flutter run -d linux
```

## Agentes

`/backend` FFI · `/frontend` shell · `/auditor` storage — `docs/audit-f3-storage.md`.
