# Copy the MSVC CRT next to encrypchat.exe. Flutter's Windows runner links
# MSVCP140 / VCRUNTIME140 / VCRUNTIME140_1 and does not ship them. On a desk
# that has Visual Studio they are already on PATH, so the app "works here"
# and dies on the first machine that only has Windows — the error names a
# missing DLL, which reads as a broken installer.
#
# App-local CRT is the documented redistributable layout and needs no admin,
# which matches the per-user NSIS installer.
#
#   powershell -File scripts\bundle-windows-crt.ps1 [ReleaseDir]

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Dest = if ($args.Count -ge 1) { $args[0] } else {
    Join-Path $Root 'apps\client\build\windows\x64\runner\Release'
}
if (-not (Test-Path $Dest)) { throw "Release folder missing: $Dest" }

$VsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $VsWhere)) { throw 'vswhere.exe not found; install Visual Studio Build Tools' }
$Vs = & $VsWhere -latest -products * -property installationPath
if (-not $Vs) { throw 'No Visual Studio installation found' }

$CrtDll = Get-ChildItem -Path (Join-Path $Vs 'VC\Redist\MSVC') `
    -Filter 'vcruntime140.dll' -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\x64\\Microsoft\.VC\d+\.CRT\\' } |
    Sort-Object FullName |
    Select-Object -Last 1
if (-not $CrtDll) { throw "No x64 Microsoft.VC*.CRT under $Vs\VC\Redist\MSVC" }

$CrtDir = $CrtDll.Directory.FullName
$Needed = @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')
foreach ($dll in $Needed) {
    $src = Join-Path $CrtDir $dll
    if (-not (Test-Path $src)) { throw "CRT folder incomplete: missing $src" }
    Copy-Item -Force $src (Join-Path $Dest $dll)
}
Write-Host "  CRT <- $CrtDir ($($Needed -join ', '))"
