# Fase 3 — Shell Flutter + FFI + almacenamiento local

**Estado:** implementado (2026-08-12)  
**Meta:** app que arranca en Linux (Fedora) y Android, crea identidad, DB local, muestra token/QR.

## Entregado

| Pieza | Ubicación |
| --- | --- |
| C ABI FFI (`0.3.0`) | `crates/core/src/ffi.rs` + `docs/ffi-contract.md` |
| Dart bindings | `apps/client/lib/core/` |
| Identidad persistente | `IdentityService` + `flutter_secure_storage` |
| DB local | `LocalDatabase` (SQLite: profile / contacts / messages) |
| UI | onboarding, chats vacío, contactos (import/export), mi token + QR |
| Brand | tokens + `assets/brand/logo-mark.png` |
| Build FFI | `make build-ffi` → `apps/client/native/libencrypchat_core.so` |

## Modelo at-rest F3 (interim, pre-SQLCipher)

Claims honestos — **no** es SQLCipher todavía:

1. **Secreto de identidad (32 bytes)** solo en OS secure storage.
2. **SQLite** en directorio privado de la app; archivo **sin** `PRAGMA key` aún.
3. **Contactos / perfil:** material público (token + pubkey + nombre).
4. **Mensajes:** columna `ciphertext BLOB` reservada; vacía hasta F4. No escribir plaintext.
5. **`db_key`** reservado en secure storage para SQLCipher/AEAD futuro; fingerprint = SHA-256 truncado (no bytes crudos de la clave).
6. Android: `allowBackup="false"` para no subir la DB a backup cloud.

Antes de F4: cablear SQLCipher (o AEAD de cuerpos) y re-auditar. Ver [audit-f3-storage.md](audit-f3-storage.md).

## DoD

- [x] Identidad persiste tras reinicio (secure storage)
- [x] QR / export-import contacto local
- [x] Gap iOS / Windows / NDK / toolchain documentado abajo
- [x] Pases `/frontend` (pass-with-notes), `/backend` (FFI), `/auditor` (pass-with-notes)
- [~] Build Linux: código + CMakeLists listos; **CMake no instalado** en el host F3
- [~] Build Android: SDK en máquina; `ANDROID_HOME` + NDK/`jniLibs` FFI pendientes en este entorno

## Gaps de plataforma (F3)

| Target | Estado |
| --- | --- |
| Android | Flutter project OK; APK falló en host F3 por toolchain Java (`java-25-openjdk` sin `JAVA_COMPILER`). NDK se instaló; falta `jniLibs` FFI + JDK 17 |
| Linux (Fedora) | Primario: FFI `.so` + `sqflite_common_ffi`. Host F3 sin paquete `cmake` → `sudo dnf install cmake gtk3-devel` para `make build-client-linux` |
| iOS | Scaffold; sin XCFramework del core → F8 |
| Windows | Scaffold; falta `encrypchat_core.dll` → F8 |

## Cómo probar

```bash
make build-ffi
make check-client
# Linux (requiere cmake + gtk3-devel):
make build-client-linux
cd apps/client && flutter run -d linux
```

## Agentes

`/backend` FFI · `/frontend` shell · `/auditor` storage — ver `docs/audit-f3-storage.md`.
