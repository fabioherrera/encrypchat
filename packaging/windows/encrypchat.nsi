; Encrypchat Windows installer. Binary repack of the Flutter release bundle,
; same idea as packaging/rpm/encrypchat.spec: this file does not compile the
; app. scripts/package-windows-installer.sh (or package-windows.ps1) builds
; the bundle first and passes the paths below.
;
; Per-user, no elevation. The analog of Linux install.sh, not of the RPM:
; nothing lands in Program Files, and Add/Remove Programs is written to HKCU.
; Chats, media and the SQLCipher key live outside this tree
; (%APPDATA%\com.encrypchat\encrypchat and Windows Credential Manager) and
; this uninstaller does not touch them. "Delete identity" inside the app is
; the way to remove those.
;
; Required -D flags (passed by the packaging script):
;   PRODUCT_VERSION   1.0.6
;   BUNDLE_DIR        absolute path of the Flutter Release folder
;   OUT_FILE          absolute path of the setup.exe to write
;   ICON_FILE         absolute path of app_icon.ico
;   LICENSE_FILE      absolute path of the license text

Unicode true
ManifestDPIAware true
SetCompressor /SOLID lzma
RequestExecutionLevel user

!ifndef PRODUCT_VERSION
  !error "PRODUCT_VERSION is required"
!endif
!ifndef BUNDLE_DIR
  !error "BUNDLE_DIR is required"
!endif
!ifndef OUT_FILE
  !error "OUT_FILE is required"
!endif
!ifndef ICON_FILE
  !error "ICON_FILE is required"
!endif
!ifndef LICENSE_FILE
  !error "LICENSE_FILE is required"
!endif

!define PRODUCT_NAME "Encrypchat"
!define PRODUCT_PUBLISHER "Encrypchat"
!define PRODUCT_WEB_SITE "https://encrypchat.com"
!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"

Name "${PRODUCT_NAME}"
OutFile "${OUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\Encrypchat"
InstallDirRegKey HKCU "Software\Encrypchat" "InstallDir"
BrandingText "Encrypchat ${PRODUCT_VERSION} — DECENTRALIZED P2P CHAT | ZERO-CLOUD"

VIProductVersion "${PRODUCT_VERSION}.0"
VIAddVersionKey "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "FileDescription" "Encrypchat desktop installer"
VIAddVersionKey "LegalCopyright" "Copyright (C) 2026 Encrypchat"
VIAddVersionKey "CompanyName" "${PRODUCT_PUBLISHER}"

!include "MUI2.nsh"
!include "FileFunc.nsh"

!define MUI_ABORTWARNING
!define MUI_ICON "${ICON_FILE}"
!define MUI_UNICON "${ICON_FILE}"

!define MUI_WELCOMEPAGE_TITLE "Encrypchat"
!define MUI_WELCOMEPAGE_TEXT "Instala el cliente de escritorio. Los chats, las fotos y las claves se quedan en este dispositivo: no hay cuenta y ningun servidor guarda una copia de una conversacion.$\r$\n$\r$\nEsta copia no esta firmada. Windows SmartScreen avisara la primera vez; el paso es Mas informacion y luego Ejecutar de todas formas.$\r$\n$\r$\nDesinstalar quita el programa. No borra tus conversaciones ni la identidad del Administrador de credenciales. Para eso, usa borrar identidad dentro de la app."

!define MUI_FINISHPAGE_RUN "$INSTDIR\encrypchat.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Abrir Encrypchat"
!define MUI_FINISHPAGE_NOAUTOCLOSE

!define MUI_UNCONFIRMPAGE_TEXT_TOP "Quita Encrypchat de este usuario. Los chats, la media y la clave privada no se van con el programa: viven en los datos de la app y en el Administrador de credenciales. Si queres borrar eso, usa borrar identidad dentro de la app antes de desinstalar."

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${LICENSE_FILE}"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Spanish"

Section "Encrypchat" SecApp
  SectionIn RO
  SetOutPath "$INSTDIR"
  ; Replace the previous install tree. User data is not here.
  RMDir /r "$INSTDIR"
  SetOutPath "$INSTDIR"
  File /r "${BUNDLE_DIR}\*.*"

  IfFileExists "$INSTDIR\encrypchat.exe" +2 0
    Abort "el bundle esta incompleto: falta encrypchat.exe"
  IfFileExists "$INSTDIR\encrypchat_core.dll" +2 0
    Abort "el bundle esta incompleto: falta encrypchat_core.dll"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\Encrypchat" "InstallDir" "$INSTDIR"

  CreateDirectory "$SMPROGRAMS\Encrypchat"
  CreateShortCut "$SMPROGRAMS\Encrypchat\Encrypchat.lnk" "$INSTDIR\encrypchat.exe" "" "$INSTDIR\encrypchat.exe" 0
  CreateShortCut "$SMPROGRAMS\Encrypchat\Desinstalar Encrypchat.lnk" "$INSTDIR\Uninstall.exe"

  WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "UninstallString" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "DisplayIcon" "$INSTDIR\encrypchat.exe"
  WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
  WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegDWORD HKCU "${PRODUCT_UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${PRODUCT_UNINST_KEY}" "NoRepair" 1

  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${PRODUCT_UNINST_KEY}" "EstimatedSize" "$0"
SectionEnd

Section "Uninstall"
  ; Intentionally not deleted:
  ;   $APPDATA\com.encrypchat\encrypchat   (SQLCipher DB + sealed media)
  ;   Windows Credential Manager           (identity + db_key)
  Delete "$SMPROGRAMS\Encrypchat\Encrypchat.lnk"
  Delete "$SMPROGRAMS\Encrypchat\Desinstalar Encrypchat.lnk"
  RMDir "$SMPROGRAMS\Encrypchat"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKCU "Software\Encrypchat"
  DeleteRegKey HKCU "${PRODUCT_UNINST_KEY}"
SectionEnd
