# Fase 8 — Paridad multiplataforma y empaquetado

**Estado:** **In progress / packaging-first** (Linux, Fedora y Android listos; Windows se compila en CI o en un host Windows y este Linux envuelve el bundle en un instalador NSIS)  
**Estrategia:** instaladores en `dist/` para probar F4–F7 en dispositivos reales. iOS sigue como gap documentado, con la ruta exacta de build para cuando haya host macOS.

## Objetivo de este corte

| Artefacto | Estado |
| --- | --- |
| Linux x64 portable `.tar.gz` + `install.sh` | **Sí** → `make package-linux` |
| Fedora `.rpm` | **Sí** → `make package-rpm` (sin firmar, sin repo detrás) |
| Android arm64 release APK | **Sí** → `make package-android` (debug-signed sideload) |
| Windows x64 `.zip` + `setup.exe` | **Sí, en dos pasos** → el `.exe` de Flutter se compila en Windows (`scripts\package-windows.ps1`) o en CI (`.github/workflows/windows.yml`); este host Linux lo envuelve con NSIS (`make package-windows`). No se cross-compila el runner MSVC |
| iOS IPA / TestFlight | **Gap** — sin macOS/firma; pasos exactos en `scripts/package-ios.sh` |
| Landing download | Enlaces a GitHub Releases; la página dice que estamos en pruebas |

### Fedora, y por qué además del tarball

El tarball se instala en el prefijo del usuario y no deja nada que el sistema
pueda seguir. En una máquina de pruebas eso se paga caro: no hay forma de saber
qué quedó de la instalación anterior, y "probar de cero" deja de significar algo.
El RPM se quita entero con `dnf remove`.

Es un repack binario, no un build desde fuente: compilar el cliente necesita el
SDK de Flutter, que Fedora no empaqueta, así que `rpmbuild` no tendría con qué.
El spec ([`packaging/rpm/encrypchat.spec`](../packaging/rpm/encrypchat.spec)) es
deliberadamente corto por eso.

Dos comprobaciones antes de escribir el fichero, porque las dos fallan en la
máquina del otro y no en la tuya: que el paquete no dependa de ninguna de las
bibliotecas que lleva dentro —eso lo haría *imposible* de instalar— y que no
anuncie esas bibliotecas al resto del sistema, donde otro paquete podría creer
que su dependencia está satisfecha por algo que no puede cargar.

### Windows, en un runner en vez de en una máquina

El runner de Flutter para Windows es un proyecto MSVC: no se cross-compila desde
Linux, y el desarrollo va en Fedora. Eso dejaba a Windows como un agujero
permanente en una de las cuatro plataformas donde el producto promete paridad,
sin siquiera poder verlo fallar. [`.github/workflows/windows.yml`](../.github/workflows/windows.yml)
lo compila en `windows-latest` y sube el zip como artefacto (30 días).

Manual a propósito —cuesta minutos y nadie necesita un build de Windows en cada
commit—, automático en los tags. Y cuesta el doble: en un repo privado el runner
de Windows factura los minutos de Actions a 2x, de modo que un build son 30-50
minutos del cupo mensual. Por eso los mismos pasos existen también como
[`scripts/package-windows.ps1`](../scripts/package-windows.ps1), para correr en
la máquina que va a probar el build —que hace falta igual— sin gastar cupo ni
esperar la descarga. Antes de subir nada verifica que
`encrypchat_core.dll` viaja junto al `.exe`: sin eso la app arranca y muestra el
cartel de core ausente, que se lee como una app rota y no como un fallo de
empaquetado.

### Rutas de compilación fuera de los binarios

El CMake de Flutter graba el árbol de compilación en el `RUNPATH` de cada
plugin, y el paquete `sqlite3` anota una ruta absoluta a la copia de SQLCipher
que construyó. Las dos nombran el directorio personal de quien compila, en un
producto cuya premisa es no filtrar cosas.

El `RUNPATH` además no es un comentario, es una instrucción para el cargador: en
la máquina que produjo el build esos directorios **sí** existen, así que una copia
instalada prefiere las bibliotecas del árbol de compilación antes que las que le
vienen dentro — precisamente en la única máquina donde nadie lo notaría.

`scripts/fix-runpath.py` los reescribe a `$ORIGIN` (lo hace a mano porque
`patchelf` no viene en Fedora; el reemplazo siempre es más corto, así que cabe
en el sitio). Los mensajes de pánico de Rust se remapean con
`--remap-path-prefix`. Y lo que quede después de eso detiene el empaquetado en
vez de viajar: hay una única excepción documentada, el URI que el snapshot AOT
de Dart guarda del registrant de plugins, para el que `gen_snapshot` no tiene
equivalente de `--remap-path-prefix`.

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

| Artefacto | Antes de adelgazar | Tras adelgazar | Hoy (F10 cerrada) |
| --- | --- | --- | --- |
| `encrypchat-android-arm64-1.0.0.apk` | ~90 MiB (94,4 MB) | 15,2 MiB (15 977 647 B) | **16,6 MiB (17 404 076 B)** |
| `encrypchat-linux-x64-1.0.0.tar.gz` | ~21 MiB (~22,0 MB) | 19,6 MiB (20 560 525 B) | **20,7 MiB (21 750 908 B)** |
| `encrypchat-1.0.0-1.fc44.x86_64.rpm` | — | — | **17,3 MiB (18 179 544 B)** |

Windows 1.0.6 (CI `windows-latest` + NSIS en este host): zip **23,1 MiB (24 180 227 B)**,
`setup.exe` **18,2 MiB (19 083 111 B)**. El instalador pesa menos porque LZMA comprime
el mismo bundle mejor que el zip de 7z.

Descomprimido en disco: APK 34,8 MB de libs extraídas; bundle Linux 47 MiB (antes 55 MiB);
RPM 51,7 MiB instalados.

La columna de hoy incluye SQLCipher y lo que entró al cerrar la fase 10. El RPM pesa menos
que el tarball porque `zstd` comprime mejor que `gzip -9`, no porque lleve menos cosas: es el
mismo bundle.

**Nota F10 (SQLCipher):** cifrar el fichero de la base cambió `libsqlite3.so`
por `libsqlcipher.so`, que trae OpenSSL enlazado estáticamente. Es una sola
librería, no dos (no hay dos copias de SQLite en el proceso), y el coste es
**+3,3 MB** sin comprimir en Linux (1,70 → 4,99 MB tras el strip) y **+2,0 MB**
de descarga en el APK (5,08 MB extraídos en el dispositivo, donde antes no
viajaba ninguna librería SQLite porque se usaba la del sistema). Las cifras de
la tabla son de antes de ese cambio.

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
| `strip --strip-unneeded` sobre la copia staged (`scripts/package-linux.sh`) | 57,6 MB → 50,4 MB sin comprimir. `libwebrtc.so` (24,5 → 19,5 MB) y `libsqlcipher.so` (5,42 → 4,99 MB) llegan con símbolos de debug del paquete prebuilt. Se hace **solo en el stage**, el bundle de `build/` queda depurable |
| Borrar `flutter_assets/NOTICES` duplicado | −1,3 MB. El engine desktop lee `NOTICES.Z` (gzip); el `NOTICES` plano es un residuo de builds viejos en `build/flutter_assets` que nunca se carga |
| `gzip -9` en el tarball | ~1 % extra |
| `tar --owner=0 --group=0 --numeric-owner` | No adelgaza, pero evita que la extracción como root intente `chown` al uid del builder y aborte |

### Descartado (y por qué)

| Idea | Decisión |
| --- | --- |
| R8/ProGuard (`isMinifyEnabled`, `isShrinkResources`) | **No aplicado.** El dex es 1,4 MB de 34,8 MB (≈0,5 MB comprimido de ganancia potencial) y el riesgo real está en reflexión/JNI de `flutter_webrtc` y `flutter_secure_storage` (el plugin nativo de `sqflite` ya no está: la base va por FFI desde F10). Sin dispositivo para regresión completa no compensa. Si se activa: reglas keep para los plugins nativos + probar llamada, fotos y keystore |
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
- El runner MSVC sigue sin cross-compilarse. Lo que este host sí hace es el instalador: `packaging/windows/encrypchat.nsi` (NSIS, por usuario, sin admin) a partir del zip de CI o de un escritorio Windows. `make package-windows` / `scripts/package-windows.sh`. Un PR que toque ese empaquetado arranca `windows.yml`.
- Falta: alguien que lo ejecute en hardware Windows real, y firma Authenticode (hoy SmartScreen avisa). Para llevar el código sin push: `git bundle create encrypchat.bundle main`.

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
- [x] Landing download: APK, RPM y tar.gz de la tanda de prueba; iOS/Windows sin URL inventada
- [x] `build.gradle.kts` listo para keystore de release opcional
- [x] Windows: regla de instalación del `.dll` del core
- [x] Fedora `.rpm`, con comprobación de que no depende de sus propias bibliotecas
- [x] Ninguna ruta de la máquina de compilación viaja en los binarios (y el empaquetado se
      detiene si aparece una nueva)
- [x] Windows: zip + instalador NSIS por usuario (`setup.exe`); CI y
      `scripts\package-windows.ps1` producen el bundle, este host lo envuelve.
      Falta **probarlo** en hardware Windows real y firmarlo.
- [ ] iOS binario real (bloqueado por host macOS)
- [ ] `crates/core` enlazado en iOS (bloqueado por macOS)
- [ ] Firma release Android ejecutada + stores
- [ ] Publicación GitHub Releases

## Agentes

`/orquestador` · `/frontend` · `/backend` · `/seo` (download copy)
