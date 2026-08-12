# Cómo probar la app (instaladores Phase 8)

Cliente usable para demo P2P en LAN: chat (F4), relay (F5), fotos (F6), llamadas WebRTC (F7). Empaquetado en `dist/`.

## Artefactos en `dist/` (recomendado)

Tras `make package` (ver [phase-8.md](phase-8.md) y [`dist/README.md`](../dist/README.md)):

| Artefacto | Ruta típica | Peso 1.0.0 |
| --- | --- | --- |
| Linux portable | `dist/encrypchat-linux-x64-<version>.tar.gz` | ~20 MB |
| Android APK (arm64) | `dist/encrypchat-android-arm64-<version>.apk` | ~16 MB |

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

APK **debug-signed** (no hay keystore de release en el repo) — OK para sideload de prueba, no para Play Store. Solo **arm64-v8a**: en un dispositivo de 32 bits o en un emulador x86_64 el `adb install` falla con `INSTALL_FAILED_NO_MATCHING_ABIS`, y eso es correcto — el core Rust solo se cross-compila para aarch64. Para emulador, usa una imagen arm64.

Si el APK anterior estaba firmado con otra clave, `adb install -r` da `INSTALL_FAILED_UPDATE_INCOMPATIBLE`: hay que `adb uninstall com.encrypchat.encrypchat` primero, lo que **borra identidad y chats locales**.

Comprobación rápida del APK (build-tools del SDK):

```bash
unzip -Z1 dist/encrypchat-android-arm64-*.apk 'lib/*' | cut -d/ -f2 | sort -u   # solo arm64-v8a
apksigner verify --print-certs dist/encrypchat-android-arm64-*.apk
```

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
4. Abrir chat y mandar texto (o adjuntar foto 🖼). En Android debe abrirse el
   **Photo Picker del sistema** sin pedir ningún permiso de galería; en un
   dispositivo antiguo sin Play Services se abre el explorador de documentos
   (también sin permiso).
5. Llamada: iconos 📞 / 📹 en el chat (ambos peers P2P online; STUN público).
6. Opcional offline chat: en Chats → ☁ configurar URL del relay (`http://IP:8787`).
7. Bloqueo: en el chat → ⋮ → **Bloquear contacto**. Desde el otro dispositivo mandá
   texto, foto y llamada: no debe llegar nada (ni bubble, ni timbre, ni fichero en
   `media/`). Corta en dos capas: el core cierra la sesión P2P con esa identidad y
   la app descarta lo que llegue por otra vía. Cerrá y reabrí la app: el bloqueo
   sigue, y el core vuelve a recibir la lista al arrancar el nodo. ⋮ →
   **Desbloquear** restaura la entrega (lo enviado mientras estaba bloqueado se
   perdió: se descartó).
8. Reporte: ⋮ → **Reportar abuso** → copia un informe al portapapeles. No sale
   nada del dispositivo. La lista de bloqueados y los enlaces legales están en
   **Mi token → Acerca de**.

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
| Fotos E2EE (P2P; relay ≤256 KiB) | Sí (F6) |
| Llamadas audio/video P2P | Sí (F7; STUN; sin TURN) |
| Relay offline LAN | Sí (F5; chat/media — no señal de llamada) |
| Bloquear / desbloquear contacto | Sí (F9; local, en las 4 plataformas) |
| Reporte de abuso | Sí (F9; informe local al portapapeles — no hay servidor que lo reciba) |
| Enlaces a privacidad y términos | Sí (F9; Mi token → Acerca de) |
| Linux / Android instaladores | Sí (`dist/`) |
| Android otras ABIs (x86_64, armeabi-v7a) | No — core Rust solo aarch64 ([phase-8.md](phase-8.md)) |
| Firma release Android | No — debug keystore; procedimiento en [phase-8.md](phase-8.md) |
| iOS / Windows package | Gap F8 — pasos exactos en `scripts/package-ios.sh` / `package-windows.sh` |
