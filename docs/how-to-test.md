# Cómo probar la app (instaladores Phase 8)

Cliente usable para demo P2P en LAN: chat (F4), relay (F5), fotos (F6), llamadas WebRTC (F7). Empaquetado en `dist/`.

## Artefactos en `dist/` (recomendado)

Tras `make package` (ver [phase-8.md](phase-8.md) y [`dist/README.md`](../dist/README.md)):

| Artefacto | Ruta típica | Peso 1.0.0 |
| --- | --- | --- |
| Fedora RPM | `dist/encrypchat-<version>-1.fc*.x86_64.rpm` | ~18 MB |
| Linux portable | `dist/encrypchat-linux-x64-<version>.tar.gz` | ~21 MB |
| Android APK (arm64) | `dist/encrypchat-android-arm64-<version>.apk` | ~17 MB |
| Windows zip + setup.exe | Bundle en CI o en una máquina Windows; este host envuelve el zip en NSIS (`make package-windows`) | ~25 MB |

### Instalar en Fedora

```bash
sudo dnf install ./dist/encrypchat-*.x86_64.rpm
encrypchat
```

Es lo preferible en una máquina de pruebas: `sudo dnf remove encrypchat` se lleva
todos los ficheros, así que "reinstalar de cero" significa lo que dice. Va sin
firmar y sin repositorio detrás, y dnf lo advierte.

Lo que **no** se lleva es tu base de datos, que vive en
`~/.local/share/com.encrypchat.encrypchat`. Es deliberado —desinstalar no debería
tirar tus chats— pero significa que para empezar de verdad de cero hay que
borrarla a mano o usar el borrado de identidad de la app.

### Instalar Linux (cualquier distribución)

```bash
tar -xzf dist/encrypchat-linux-x64-*.tar.gz
cd encrypchat-linux-x64-*
./install.sh
encrypchat
```

Instala en `~/.local/share/encrypchat`, symlink `~/.local/bin/encrypchat`, desktop entry en `~/.local/share/applications/`.

### Instalar Windows

El runner de Flutter para Windows es un proyecto MSVC: este host no produce
`encrypchat.exe`. Sí produce el **instalador** (`setup.exe`) a partir de un
bundle que ya exista — CI o un escritorio Windows.

```bash
make package-windows
# → dist/encrypchat-windows-x64-<version>-setup.exe
```

El instalador es por usuario (sin admin): menú Inicio y
`%LOCALAPPDATA%\Programs\Encrypchat`. Desinstalar deja los chats y la identidad
en el Administrador de credenciales; «borrar identidad» dentro de la app es lo
que los quita. Sin firmar: SmartScreen → «Más información» → «Ejecutar de
todas formas».

**El bundle**, si todavía no está en `dist/`:

En la propia máquina Windows (la que va a probarlo):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\package-windows.ps1
```

Necesita Rust (rustup), Flutter en el PATH, Visual Studio con "Desktop
development with C++" y el Modo de desarrollador activado —Flutter enlaza los
plugins con symlinks y sin eso falla con un error que parece de toolchain—.
Con NSIS (`choco install nsis`) ese script también escribe el `setup.exe`.

O CI (el repo es público; el runner no factura). Un PR que toque
`packaging/windows` o `windows.yml` lo arranca; desde un token con
`actions:write` también `gh workflow run windows.yml`.

```bash
ENCRYPCHAT_WINDOWS_RUN=<id> make package-windows
# sin el id, make package-windows solo acepta un artefacto de main/tag,
# nunca el último success de un PR (mismo número de versión, otros bits).
```

Nadie lo ha ejecutado todavía en hardware real — si algo falla, ese es el
primer sitio donde mirar.

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

1. Ambos crean identidad. Uno abre **Mi token** y muestra el QR; el otro va a
   **Contactos → Escanear QR** y apunta la cámara. En Linux y Windows no hay
   cámara en vivo: **Pegar export**, o una foto del QR. Hace falta el intercambio
   en los dos sentidos.
2. Chats → icono link → copiar multiaddr / puerto.
3. El otro conecta con IP LAN + puerto.
4. Abrir chat y mandar texto (o adjuntar foto 🖼). En Android debe abrirse el
   **Photo Picker del sistema** sin pedir ningún permiso de galería; en un
   dispositivo antiguo sin Play Services se abre el explorador de documentos
   (también sin permiso).
5. Llamada: iconos 📞 / 📹 en el chat (ambos peers P2P online; STUN público).
6. Opcional offline chat: en Chats → ☁ configurar URL del relay (`http://IP:8787`).
   Cerrá la app del destinatario, mandale texto y una foto (queda ☁ *vía relay*), y
   abrila: llegan atribuidos al remitente real, que sale del propio criptograma —
   ya no hay campo `from` que declarar. Mandá lo mismo dos veces desde el relay y
   fijate que no aparece duplicado. **Dejá la app abierta un par de minutos después
   de recibir**: el relay ya no borra al entregar, entrega otra vez a los 60 s y esa
   segunda copia tiene que morir en la deduplicación por `msg_id` — nada nuevo en
   pantalla, ni bubble ni fichero repetido. Probalo en un móvil y en desktop, que es
   donde se ve si el buzón local aguanta la reentrega. Los dos extremos tienen que ir en `0.8.0`: con
   un core anterior la app no arranca y lo dice en pantalla. Si el relay entrega
   algo que no cuadra, en Chats sale un aviso; el detalle por motivo está en ☁.
7. Bloqueo: en el chat → ⋮ → **Bloquear contacto**. Desde el otro dispositivo mandá
   texto, foto y llamada: no debe llegar nada (ni bubble, ni timbre, ni fichero en
   `media/`). Corta en dos capas: el core cierra la sesión P2P con esa identidad y
   la app descarta lo que llegue por otra vía. Cerrá y reabrí la app: el bloqueo
   sigue, y el core vuelve a recibir la lista al arrancar el nodo. ⋮ →
   **Desbloquear** restaura la entrega (lo enviado mientras estaba bloqueado se
   perdió: se descartó). Probalo también **con una llamada en curso**: al bloquear,
   la llamada se corta en los dos dispositivos y el indicador de cámara/micro del
   sistema se apaga.
8. Desconocidos: borrá el contacto en un dispositivo y mandale texto desde el otro.
   No aparece en la lista de chats: sale la tarjeta **Solicitudes** arriba, sin
   sonido ni notificación. Dentro se ve el token, el texto y qué se rechazó.
   Mandale ahora una foto o una llamada desde el mismo token: no llegan (en Chats
   sale el aviso de motivo). Después de 5 mensajes suyos, los siguientes se
   descartan. **Aceptar** lo vuelve contacto y a partir de ahí sí entran fotos y
   llamadas; **Descartar** borra sus mensajes y sus ficheros de `media/`.
9. Reporte: ⋮ → **Reportar abuso** → **Guardar informe…** escribe un `.txt`. En
   Linux y Windows elegís la ruta; en Android e iOS no hay diálogo de guardado y
   va a una carpeta de la app (en iOS visible desde Archivos). Copiar al
   portapapeles sigue estando como segunda acción. No sale nada del dispositivo
   por ninguno de los dos caminos. La lista de bloqueados y los enlaces legales
   están en **Mi token → Acerca de**.

## Comprobar que la base local está cifrada (F10)

Con la app cerrada, sobre el fichero real:

```bash
DB="$(find ~/.local/share -name encrypchat_v1.db | head -1)"
sqlite3 "$DB" .tables          # Error: in prepare, file is not a database (26)
head -c 15 "$DB"               # no dice "SQLite format 3"
grep -c "<nombre de un contacto>" "$DB"   # 0
```

Si venís de una versión anterior, el primer arranque convierte la base plana:
los chats, contactos y bloqueos siguen ahí y no debe quedar ningún
`encrypchat_v1.db.plaintext-backup` ni `.encrypting` en el directorio. Si el
llavero del sistema perdió la clave, la app lo dice en pantalla en vez de
empezar una base nueva encima de la vieja.

## Entrada malformada (fuzzing de decodificadores)

Todo lo que decodifica bytes de un desconocido —`ECS1` sellado, handshake `EH02`,
frame `EC04`, PoP y los cuerpos JSON del relay— tiene una propiedad en
`crates/core/src/fuzz.rs` y `services/relay/tests/malformed.rs`: **ninguna
entrada puede provocar pánico, desbordamiento, asignación sin límite ni
cuelgue**; un `Err` siempre vale. Los generadores no tiran bytes al azar contra
una cabecera mágica (rebotarían en el primer `if`): parten de un artefacto
válido y lo dañan, o construyen uno que pasa magic, versión y longitud y miente
más adentro.

Corren dentro de `make check-rust` en menos de dos segundos. Para una pasada
profunda, la misma que hace el job nocturno:

```bash
PROPTEST_CASES=300000 cargo test --release -p encrypchat_core --lib fuzz
PROPTEST_CASES=50000  cargo test --release -p encrypchat_relay --test malformed
```

Si algo falla, proptest reduce el caso al mínimo y lo guarda en
`crates/core/proptest-regressions/`: ese fichero **se commitea** junto al
arreglo, y a partir de ahí se reejecuta antes que cualquier caso nuevo.

Lo que esto **no** da, y `cargo-fuzz` sí: guía por cobertura. Se descartó porque
necesita nightly, y un fuzzer que no entra en CI se corre el día que se escribe y
nunca más. Los límites de memoria se miden aparte, con un allocator instrumentado,
en `crates/core/tests/allocation.rs`.

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
| Identidad + QR/contactos | Sí (cámara en Android/iOS; en Linux/Windows, imagen o pegar) |
| Chat 1:1 E2EE + handshake EH02 | Sí (hasta `0.7.x` era EH01, que no autenticaba — F-1) |
| Fotos E2EE (P2P; relay ≤256 KiB) | Sí (F6) |
| Llamadas audio/video P2P | Sí (F7; STUN; sin TURN) |
| Relay offline LAN | Sí (F5; chat/media — no señal de llamada) |
| Remitente autenticado por relay | Sí (`ECS1` sealed sender + anti-replay por `msg_id`; core `0.8.0` — [audit-f10.md](audit-f10.md) F-2) |
| Bloquear / desbloquear contacto | Sí (F9; local, en las 4 plataformas; corta la llamada en curso) |
| Bandeja de solicitudes (no-contactos) | Sí (F10; solo texto, 20 remitentes × 5 mensajes, sin sonar — [audit-f10.md](audit-f10.md) F-6) |
| Cuota de adjuntos entrantes | Sí (F10; 512 MiB por par, 2 GiB total) |
| Reporte de abuso | Sí (F9/F-14; informe local guardado en un archivo — no hay servidor que lo reciba) |
| Enlaces a privacidad y términos | Sí (F9; Mi token → Acerca de) |
| Base local cifrada de fichero completo | Sí (F10; SQLCipher + cuerpos AEAD — [audit-f3-storage.md](audit-f3-storage.md)) |
| Fedora / Linux / Android instaladores | Sí (`dist/`) |
| Windows instalador | Sí: bundle en CI/Windows, `setup.exe` NSIS desde este host (`make package-windows`) — sin firmar y sin probar en hardware |
| Android otras ABIs (x86_64, armeabi-v7a) | No — core Rust solo aarch64 ([phase-8.md](phase-8.md)) |
| Firma release Android | No — debug keystore; procedimiento en [phase-8.md](phase-8.md) |
| iOS package | Gap F8 — necesita host macOS; pasos exactos en `scripts/package-ios.sh` |
