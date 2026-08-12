# Fase 8 — Paridad multiplataforma y empaquetado

**Estado:** **In progress / packaging-first** (2026-08-12)  
**Estrategia:** producir instaladores **ahora** para probar F4 en dispositivos reales. **F5–F7** (relay, media, WebRTC) quedan **diferidos** hasta tener builds instalables en Linux + Android.

## Objetivo de este corte

| Artefacto | Estado |
| --- | --- |
| Linux x64 portable `.tar.gz` + `install.sh` | **Sí** → `dist/` vía `make package-linux` |
| Android arm64 release APK | **Sí** → `dist/` vía `make package-android` (debug-signed sideload) |
| Windows installer | **Gap** — script stub; requiere host Windows |
| iOS IPA / TestFlight | **Gap** — script stub; requiere macOS + signing |
| Landing download | Copia honesta: builds locales / Releases futuros — sin URLs inventadas |

## Cómo buildar

Toolchain típica en este monorepo (gitignored): `.tools/bin` (cmake/ninja), `.tools/flutter`, `.tools/jdk-21`, `.tools/pkgconfig`, NDK bajo `$HOME/Android/Sdk/ndk/…`.

```bash
# Desde la raíz
export PATH="$PWD/.tools/bin:$PATH"
export PKG_CONFIG_PATH="$PWD/.tools/pkgconfig"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"

make package            # linux + android
# o por plataforma:
make package-linux
make package-android
```

Salida documentada en [`dist/README.md`](../dist/README.md).

### Linux install

```bash
tar -xzf dist/encrypchat-linux-x64-<ver>.tar.gz
cd encrypchat-linux-x64-<ver> && ./install.sh
encrypchat   # ~/.local/bin en PATH
```

### Android install

```bash
adb install -r dist/encrypchat-android-arm64-<ver>.apk
```

APK firmado con keystore de **debug** de Flutter si no hay release keystore — válido para sideload de prueba, **no** para Play Store.

## Scripts

| Script | Rol |
| --- | --- |
| `scripts/package-linux.sh` | `make build-ffi` + `flutter build linux --release` → tarball |
| `scripts/package-android.sh` | NDK arm64 core → jniLibs + `flutter build apk --release` |
| `scripts/package-all.sh` | Linux + Android |
| `scripts/package-windows.sh` | Stub (exit 2) + instrucciones |
| `scripts/package-ios.sh` | Stub (exit 2) + instrucciones |

## Gaps (honestos)

| Target | Bloqueo |
| --- | --- |
| Windows | Sin host Windows / MSVC en este builder; no se fabrican `.exe` falsos |
| iOS | Sin Mac / Xcode / Apple signing; no se fabrican IPA placeholder |
| Play / App Store | Firma release + compliance = F9 |
| Flatpak / RPM | No en este corte; tarball portable + desktop entry sí |

## Relación con F5–F7

Orden de producto habitual: F5 relay → F6 media → F7 WebRTC → F8 packaging.  
**Decisión de proyecto:** packaging-first para poder instalar y demos LAN **antes** de relay/media/llamadas. Roadmap refleja F5 como diferido tras instaladores.

## DoD parcial (este corte)

- [x] `dist/` gitignored excepto README
- [x] Scripts + Makefile `package*`
- [x] Linux tarball instalable + Android APK en `dist/`
- [x] Docs / how-to-test / roadmap / AGENTS actualizados
- [x] Landing download sin URLs 404
- [ ] Windows / iOS binarios reales
- [ ] Firma release Android + stores
- [ ] Publicación GitHub Releases

## Agentes

`/orquestador` (coord), `/frontend` (Flutter bundle), `/backend` (FFI NDK), `/seo` (download copy)
