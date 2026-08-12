# Cómo probar la app (sin esperar F5–F8)

Fase 4 + EH01 ya son un **cliente usable** para demo P2P en LAN. No hace falta relay, media ni tiendas para instalar y probar.

## Qué sí tenés hoy

| Pieza | Estado |
| --- | --- |
| Identidad + QR/contactos | Sí |
| Chat 1:1 E2EE online | Sí |
| Hello autenticado (EH01) | Sí (`0.5.0`) |
| Cuerpos sellados en DB | Sí |
| Offline / relay | No (F5) — peer apagado = error explícito |

## Bloqueo = toolchain del host, no fases de producto

En esta máquina (Fedora) faltaba:

```bash
# Linux desktop build
sudo dnf install cmake ninja-build clang gtk3-devel

# Android APK (javac; tenés JRE 25 sin compiler)
sudo dnf install java-21-openjdk-devel
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
export ANDROID_HOME=$HOME/Android/Sdk
```

Luego:

```bash
# desde la raíz del monorepo
make build-ffi

# Linux
make build-client-linux
# o: cd apps/client && flutter run -d linux

# Android (después de JDK + SDK)
cd apps/client
flutter build apk --debug
# Instalar: adb install build/app/outputs/flutter-apk/app-debug.apk
# Nota: falta copiar libencrypchat_core.so a jniLibs (cargo-ndk) para crypto/P2P en device
```

## Demo 2 dispositivos (misma Wi‑Fi)

1. Ambos crean identidad e importan el contacto del otro.  
2. Chats → icono link → copiar multiaddr / puerto.  
3. El otro conecta con IP LAN + puerto.  
4. Abrir chat y mandar texto.

iOS / Windows empaquetados = **Fase 8**, no bloquean probar en Linux o Android con NDK.
