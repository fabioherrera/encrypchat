# Build the Windows release on Windows -> dist\encrypchat-windows-x64-<version>.zip
#
# ASCII only, on purpose: Windows PowerShell 5.1 reads a .ps1 without a BOM as
# ANSI, so an em dash here would reach the screen as mojibake.
#
# Same steps as .github/workflows/windows.yml, for the case that workflow does not
# cover: a hosted runner costs Actions minutes at double rate on Windows, and the
# machine that is going to *test* this build is a Windows machine anyway. Building
# there costs nothing and skips the download.
#
# Run from anywhere; the script locates the repo from its own path:
#
#   powershell -ExecutionPolicy Bypass -File scripts\package-windows.ps1
#
# The result is unsigned. SmartScreen will warn on first run, and the way past it
# is "More info" -> "Run anyway". Do not hand this to anyone as a release.

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$File,
        [Parameter(ValueFromRemainingArguments)][string[]]$Arguments
    )
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$File $($Arguments -join ' ') exited with $LASTEXITCODE"
    }
}

function Assert-Tool {
    param([string]$Name, [string]$HowToGetIt)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is not on PATH. $HowToGetIt"
    }
}

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Pubspec = Join-Path $Root 'apps\client\pubspec.yaml'
$VersionMatch = Select-String -Path $Pubspec -Pattern '^version:\s*([^+\s]+)' | Select-Object -First 1
if (-not $VersionMatch) { throw "no version line in $Pubspec" }
$Version = $VersionMatch.Matches[0].Groups[1].Value
$Bundle = Join-Path $Root 'apps\client\build\windows\x64\runner\Release'
$Zip = Join-Path $Root "dist\encrypchat-windows-x64-$Version.zip"

Write-Host "Encrypchat $Version - Windows x64" -ForegroundColor Cyan

# Checked up front because each of these fails deep inside a build that has
# already run for minutes, with an error that names a toolchain and not the thing
# to install.
Assert-Tool 'cargo' 'Install Rust from https://rustup.rs (the MSVC default host is the right one).'
Assert-Tool 'rustup' 'Install Rust from https://rustup.rs - the MSVC target is added below.'
Assert-Tool 'flutter' 'Install Flutter for Windows and put its bin\ on PATH.'

$ProgramFilesX86 = ${env:ProgramFiles(x86)}
$VsWhere = if ($ProgramFilesX86) {
    Join-Path $ProgramFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
} else { $null }
if ($VsWhere -and (Test-Path $VsWhere)) {
    $vs = & $VsWhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property displayName
    if (-not $vs) {
        throw ('No Visual Studio with the "Desktop development with C++" workload. ' +
            'The Flutter Windows runner is an MSVC project and cannot build without it: ' +
            'install it from the Visual Studio Installer (Build Tools are enough).')
    }
    Write-Host "  MSVC: $vs"
} else {
    Write-Warning 'vswhere.exe not found; cannot confirm the C++ toolchain is installed.'
}

# Pinned in CI, so a mismatch here is the difference between "it built on the
# runner" and "it built on this desk". Not fatal: a newer stable usually works,
# and a version string this script failed to read is no reason to stop a build.
try {
    $FlutterVersion = (& flutter --version --machine | ConvertFrom-Json).frameworkVersion
    if ($FlutterVersion -ne '3.44.9') {
        Write-Warning "Flutter $FlutterVersion; CI builds with 3.44.9."
    }
} catch {
    Write-Warning 'Could not read the Flutter version; CI builds with 3.44.9.'
}

Write-Host '==> Rust core (x86_64-pc-windows-msvc)' -ForegroundColor Cyan
Invoke-Native 'rustup' 'target' 'add' 'x86_64-pc-windows-msvc'
Push-Location $Root
try {
    # Panic messages carry the path of the source file that raised them, and there
    # is no reason to ship the layout of this machine's home directory. Same remap
    # the Makefile and the workflow use.
    $remap = "--remap-path-prefix=$Root=/encrypchat"
    $env:RUSTFLAGS = if ($env:RUSTFLAGS) { "$remap $env:RUSTFLAGS" } else { $remap }
    Invoke-Native 'cargo' 'build' '-p' 'encrypchat_core' '--release' '--target' 'x86_64-pc-windows-msvc'
} finally {
    Pop-Location
}

$TargetDir = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $Root 'target' }
$Dll = Join-Path $TargetDir 'x86_64-pc-windows-msvc\release\encrypchat_core.dll'
if (-not (Test-Path $Dll)) { throw "cargo reported success but $Dll is missing" }

# windows\CMakeLists.txt installs the DLL from here next to encrypchat.exe, and
# native_library.dart looks there first.
$Native = Join-Path $Root 'apps\client\native'
New-Item -ItemType Directory -Force -Path $Native | Out-Null
Copy-Item -Force $Dll $Native
Write-Host "  native\ <- encrypchat_core.dll"

Write-Host '==> Flutter client (release)' -ForegroundColor Cyan
Push-Location (Join-Path $Root 'apps\client')
try {
    Invoke-Native 'flutter' 'config' '--enable-windows-desktop'
    Invoke-Native 'flutter' 'pub' 'get'
    try {
        Invoke-Native 'flutter' 'build' 'windows' '--release' '--tree-shake-icons'
    } catch {
        # The one failure that reads as a toolchain problem and is not: plugins are
        # linked with symlinks, which unprivileged Windows refuses to create.
        Write-Warning ('If the error mentions symlink support, turn on Developer Mode: ' +
            'start ms-settings:developers')
        throw
    }
} finally {
    Pop-Location
}

# The likeliest way this ships broken is an .exe that starts and then shows the
# core-missing banner, which looks like a broken app rather than a packaging slip.
foreach ($needed in 'encrypchat.exe', 'encrypchat_core.dll', 'data') {
    $path = Join-Path $Bundle $needed
    if (-not (Test-Path $path)) { throw "the build is incomplete: missing $needed in $Bundle" }
}

Write-Host '==> Package' -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path (Split-Path $Zip) | Out-Null
if (Test-Path $Zip) { Remove-Item -Force $Zip }
# PDBs carry the builder path and are not needed to run. Copy first so the
# Flutter build tree stays debuggable.
$ZipStage = Join-Path $Root 'dist\.stage-windows-zip'
if (Test-Path $ZipStage) { Remove-Item -Recurse -Force $ZipStage }
Copy-Item -Path $Bundle -Destination $ZipStage -Recurse
Get-ChildItem -Path $ZipStage -Recurse -Filter *.pdb -File | Remove-Item -Force
Compress-Archive -Path (Join-Path $ZipStage '*') -DestinationPath $Zip
Remove-Item -Recurse -Force $ZipStage
$MiB = [math]::Round((Get-Item $Zip).Length / 1MB, 1)

Write-Host "  zip: $Zip ($MiB MiB)"

# Same NSIS script the Linux host compiles after downloading this zip. On a
# machine that already has makensis (CI installs it; a desk may not) we wrap
# the bundle here so the tester gets a Start Menu entry and an uninstaller
# without a second hop.
$Installer = Join-Path $Root 'scripts\package-windows-installer.sh'
$Setup = Join-Path $Root "dist\encrypchat-windows-x64-$Version-setup.exe"
$Bash = Get-Command 'bash' -ErrorAction SilentlyContinue
if ($Bash) {
    Write-Host '==> NSIS installer' -ForegroundColor Cyan
    Invoke-Native $Bash.Source $Installer $Bundle
} else {
    Write-Warning "bash not on PATH; zip is ready, installer skipped. On Linux: scripts/package-windows-installer.sh $Zip"
}

Write-Host ''
Write-Host "OK: $Zip ($MiB MiB)" -ForegroundColor Green
if (Test-Path $Setup) {
    $SetupMiB = [math]::Round((Get-Item $Setup).Length / 1MB, 1)
    Write-Host "OK: $Setup ($SetupMiB MiB)" -ForegroundColor Green
}
Write-Host 'The zip runs in place. The setup.exe is per-user (no admin): Start Menu'
Write-Host 'and %LOCALAPPDATA%\Programs\Encrypchat. Uninstall leaves chats and the'
Write-Host 'identity in Credential Manager — use "borrar identidad" inside the app.'
Write-Host 'Unsigned: SmartScreen warns on first run ("More info" -> "Run anyway").'
Write-Host 'It works if the app reaches the identity screen instead of the core-missing banner.'
