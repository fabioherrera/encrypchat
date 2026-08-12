# Cómo probar la app (instaladores Phase 8)

Fase 4 + EH01 ya son un **cliente usable** para demo P2P en LAN. Empaquetado packaging-first: instaladores en `dist/` sin esperar F5–F7 (relay/media/WebRTC diferidos).

## Artefactos en `dist/` (recomendado)

Tras `make package` (ver [phase-8.md](phase-8.md) y [`dist/README.md`](../dist/README.md)):

| Artefacto | Ruta típica |
| --- | --- |
| Linux portable | `dist/encrypchat-linux-x64-<version>.tar.gz` |
| Android APK (arm64) | `dist/encrypchat-android-arm64-<version>.apk` |

### Instalar Linux

```bash
tar -xzf dist/encrypchat-linux-x64-*.tar.gz
cd encrypchat-linux-x64-*
./install.sh
encrypchat
```

Instala en `~/.local/share/encrypchat`, symlink `~/.local/bin/encrypchat`, desktop entry en `~/.local/share/applications/`.

### Instalar Android

```bash
adb install -r dist/encrypchat-android-arm64-*.apk
```

APK **debug-signed** (Flutter default sin keystore de release) — OK para sideload de prueba, no para Play Store.

## Builds intermedios (sin empaquetar)

| Artefacto | Ruta |
| --- | --- |
| Linux bundle | `apps/client/build/linux/x64/release/bundle/encrypchat` |
| Android APK (flutter out) | `apps/client/build/app/outputs/flutter-apk/app-release.apk` |
| Core Linux `.so` | `apps/client/native/libencrypchat_core.so` |
| Core Android arm64 | `apps/client/android/app/src/main/jniLibs/arm64-v8a/` |

```bash
./apps/client/build/linux/x64/release/bundle/encrypchat
```

## Demo 2 dispositivos (misma Wi‑Fi)

1. Ambos crean identidad e importan el contacto del otro.
2. Chats → icono link → copiar multiaddr / puerto.
3. El otro conecta con IP LAN + puerto.
4. Abrir chat y mandar texto.

## Toolchain portable (`.tools/`, gitignored)

Sin `sudo dnf`: cmake, ninja, wrappers clang→g++, JDK 21 Temurin, headers libsecret.

```bash
export PATH="$PWD/.tools/bin:$PATH"
export PKG_CONFIG_PATH="$PWD/.tools/pkgconfig"
export JAVA_HOME="$PWD/.tools/jdk-21"
export ANDROID_HOME=$HOME/Android/Sdk
make package
```

## Qué incluye / qué no

| Pieza | Estado |
| --- | --- |
| Identidad + QR/contactos | Sí |
| Chat 1:1 E2EE + EH01 | Sí |
| Linux / Android instaladores | Sí (`dist/`) |
| Relay offline | F5 (diferido) |
| iOS / Windows package | Gap F8 — stubs en `scripts/package-ios.sh` / `package-windows.sh` |
