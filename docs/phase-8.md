# Fase 8 — Paridad multiplataforma y empaquetado

**Estado:** **In progress / packaging-first** (Linux + Android listos y adelgazados)  
**Estrategia:** instaladores en `dist/` para probar F4–F7 en dispositivos reales. Windows/iOS siguen como gaps documentados, con la ruta exacta de build para cuando haya host.

## Objetivo de este corte

| Artefacto | Estado |
| --- | --- |
| Linux x64 portable `.tar.gz` + `install.sh` | **Sí** → `make package-linux` |
| Android arm64 release APK | **Sí** → `make package-android` (debug-signed sideload) |
| Windows installer | **Gap** — sin host Windows; pasos exactos en `scripts/package-windows.sh` |
| iOS IPA / TestFlight | **Gap** — sin macOS/firma; pasos exactos en `scripts/package-ios.sh` |
| Landing download | Copia honesta: builds locales / Releases futuros — sin URLs inventadas |

## Qué incluye el paquete actual

Identidad, chat P2P E2EE (EH01), relay offline opcional (F5), fotos E2EE (F6), llamadas WebRTC (F7).

## Cómo buildar

```bash
export PATH="$PWD/.tools/bin:$PATH"
export PKG_CONFIG_PATH="$PWD/.tools/pkgconfig"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export JAVA_HOME="${JAVA_HOME:-$PWD/.tools/jdk-21}"

make package            # linux + android → dist/
```

Salida: [`dist/README.md`](../dist/README.md). Guía de prueba: [how-to-test.md](how-to-test.md).

## Peso de artefactos

Medido en el mismo host, versión 1.0.0 (con WebRTC F7 dentro):

| Artefacto | Antes | Ahora | Δ |
| --- | --- | --- | --- |
| `encrypchat-android-arm64-1.0.0.apk` | ~90 MiB (94,4 MB) | **15,2 MiB (15 977 647 B)** | **−83 %** |
| `encrypchat-linux-x64-1.0.0.tar.gz` | ~21 MiB (~22,0 MB) | **19,6 MiB (20 560 525 B)** | −7 % |

Descomprimido en disco: APK 34,8 MB de libs extraídas; bundle Linux 47 MiB (antes 55 MiB).

### Android — de dónde sale la reducción

| Cambio | Efecto |
| --- | --- |
| `abiFilters = ["arm64-v8a"]` en `android/app/build.gradle.kts` + `flutter build apk --target-platform android-arm64` | Quita `x86_64` y `armeabi-v7a`: 95 MB → 34,8 MB sin comprimir. Eran ABIs **inservibles**: `libencrypchat_core.so` solo se cross-compila para aarch64, así que esas variantes instalaban una app que muere al cargar el FFI. `flutter_webrtc` era el peor ofensor (`libjingle_peerconnection_so.so` x86_64 + v7a ≈ 23 MB) |
| `packaging { jniLibs { useLegacyPackaging = true } }` | Comprime los `.so` dentro del APK: 32,5 MB → 14,9 MB en el zip (`extractNativeLibs=true`). Contrapartida: en el dispositivo Android extrae las libs, así que ocupa ~35 MB en disco. Para un AAB de Play esto lo recalcula el servidor |
| `[profile.release] strip = "symbols"` en `Cargo.toml` | El `.so` de Android ya venía casi sin símbolos (1 097 584 → 1 095 376 B). Donde sí importa es en Linux |
| Verificación en `scripts/package-android.sh` | Falla el empaquetado si aparece un ABI sin su `libencrypchat_core.so`, o si falta el core en arm64 |

Los 18 símbolos FFI exportados sobreviven al strip (viven en `.dynsym`); comprobado con `readelf --dyn-syms` en x86-64 y aarch64, y `make check-client` corre los tests contra el `.so` stripped.

### Linux — de dónde sale la reducción

| Cambio | Efecto |
| --- | --- |
| `strip --strip-unneeded` sobre la copia staged (`scripts/package-linux.sh`) | 57,6 MB → 50,4 MB sin comprimir. `libwebrtc.so` (24,5 → 19,5 MB) y `libsqlite3.so` llegan con símbolos de debug del paquete prebuilt. Se hace **solo en el stage**, el bundle de `build/` queda depurable |
| Borrar `flutter_assets/NOTICES` duplicado | −1,3 MB. El engine desktop lee `NOTICES.Z` (gzip); el `NOTICES` plano es un residuo de builds viejos en `build/flutter_assets` que nunca se carga |
| `gzip -9` en el tarball | ~1 % extra |
| `tar --owner=0 --group=0 --numeric-owner` | No adelgaza, pero evita que la extracción como root intente `chown` al uid del builder y aborte |

### Descartado (y por qué)

| Idea | Decisión |
| --- | --- |
| R8/ProGuard (`isMinifyEnabled`, `isShrinkResources`) | **No aplicado.** El dex es 1,4 MB de 34,8 MB (≈0,5 MB comprimido de ganancia potencial) y el riesgo real está en reflexión/JNI de `flutter_webrtc`, `flutter_secure_storage` y `sqflite`. Sin dispositivo para regresión completa no compensa. Si se activa: reglas keep para los plugins nativos + probar llamada, fotos y keystore |
| `--split-per-abi` | Innecesario: con un único ABI produce el mismo APK con nombre distinto y rompe rutas en docs/scripts |
| Font subsetting en desktop (`--tree-shake-icons`) | El flag ya se pasa, pero **es no-op en desktop** en Flutter 3.44.9: `flutter_tools/bin/tool_backend.dart` manda `-dTreeShakeIcons="true"` con comillas literales, y `IconTreeShaker.enabled` compara con `'true'`. Resultado: `MaterialIcons-Regular.otf` viaja completo (1,6 MB) en Linux, mientras en Android sí se reduce a 4,4 KB. No se parchea el SDK vendored |
| `lto`/`opt-level="z"` en Cargo | Ganancia marginal (<0,3 MB sobre 34,8 MB) a cambio de tiempos de build y de tocar el perfil de crypto. No se hizo |
| Cambiar `.tar.gz` por `.tar.xz` | Comprime mejor pero cambia el artefacto publicado y las instrucciones ya difundidas. Pendiente de decisión de release |

## Firma release Android

Hoy el APK de `dist/` va **firmado con la keystore de debug** (sideload). El proyecto ya está preparado para firma real sin romper el build cuando no hay keystore:

`android/app/build.gradle.kts` lee `android/key.properties` (gitignored) si existe; si no existe, cae a la config `debug`.

```properties
# apps/client/android/key.properties  (NO se commitea)
storeFile=/ruta/absoluta/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Generar la keystore (una vez, fuera del repo):

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Con ese archivo presente, `make package-android` firma con la keystore de release y lo dice en el log. Sin `key.properties` el build **no falla**: `hasReleaseKeystore` queda en false y `buildTypes.release` cae al `signingConfig` de debug, que es lo que hace CI hoy.

Para Play hace falta un **AAB**, no el APK de `dist/`:

```bash
cd apps/client
flutter build appbundle --release --target-platform android-arm64
# build/app/outputs/bundle/release/app-release.aab
```

Este repo **no** contiene keystores ni secretos: `key.properties`, `*.jks` y `*.keystore` están en `.gitignore`. La keystore y sus contraseñas viven fuera del repo (gestor de secretos u offline); perderla obliga a publicar con otro `applicationId` salvo que Play App Signing ya tenga la clave de firma.

Ojo al cambiar de firma: Android rechaza actualizar un APK firmado con otra clave (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). Hay que desinstalar, y **desinstalar borra la base local cifrada** (identidad, chats, media). Avisar antes de repartir un APK con clave nueva.

## Windows / iOS — estado real

Ninguno se puede buildar en este host Linux. Lo que sí quedó verificado/preparado:

**Windows**

- `windows/flutter/generated_plugin_registrant.cc` registra `flutter_webrtc`, `flutter_secure_storage_windows` y `file_selector_windows`.
- `windows/CMakeLists.txt` ahora instala `apps/client/native/encrypchat_core.dll` junto al `.exe`, que es el primer candidato de `lib/core/native_library.dart`. Antes no había regla: el bundle habría salido sin el core.
- `image_picker` no tiene implementación Windows → adjuntar fotos usa el fallback `file_selector`, igual que Linux.
- Falta: host Windows + VS 2022 para `flutter build windows --release` y empaquetar el zip/MSIX. Pasos exactos: `scripts/package-windows.sh`.

**iOS**

- `ios/Runner/Info.plist` con `NSMicrophoneUsageDescription` y `NSCameraUsageDescription`.
- `ios/Runner/GeneratedPluginRegistrant.m` registra `flutter_webrtc`, `image_picker_ios`, `sqflite_darwin`, `flutter_secure_storage`.
- `IPHONEOS_DEPLOYMENT_TARGET = 13.0` coincide con lo que exige `flutter_webrtc` 1.6.0 (`WebRTC-SDK` pide iOS 13+).
- Falta (solo en Mac): compilar `crates/core` para `aarch64-apple-ios` y enlazar `libencrypchat_core.a` en el target Runner con `-force_load` (si no, el linker elimina los símbolos y `DynamicLibrary.process()` falla), `pod install`, firma Apple y `flutter build ipa`. Pasos exactos: `scripts/package-ios.sh`.
- `ios/Podfile` no está commiteado: lo genera Flutter en el primer build en macOS.

## DoD parcial (este corte)

- [x] `dist/` gitignored excepto README
- [x] Scripts + Makefile `package*`
- [x] Linux tarball + Android APK
- [x] APK adelgazado a un solo ABI útil (arm64-v8a) con verificación automática
- [x] Docs / how-to-test / roadmap actualizados
- [x] Landing download sin URLs 404
- [x] `build.gradle.kts` listo para keystore de release opcional
- [x] Windows: regla de instalación del `.dll` del core
- [ ] Windows / iOS binarios reales (bloqueado por host)
- [ ] `crates/core` enlazado en iOS (bloqueado por macOS)
- [ ] Firma release Android ejecutada + stores
- [ ] Publicación GitHub Releases

## Agentes

`/orquestador` · `/frontend` · `/backend` · `/seo` (download copy)
