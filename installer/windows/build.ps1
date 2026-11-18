# Compile le launcher en release puis génère l'installeur Windows.
# Usage : powershell -ExecutionPolicy Bypass -File installer\windows\build.ps1
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

Write-Host '>> cargo build --release'
Push-Location $root
try { cargo build --release } finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { throw "cargo build a échoué (code $LASTEXITCODE)." }

# Inno Setup s'installe soit par machine (Program Files), soit par utilisateur (winget).
$candidates = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
)
$iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    throw "Inno Setup 6 introuvable. Installe-le : winget install -e --id JRSoftware.InnoSetup"
}

& $iscc (Join-Path $PSScriptRoot 'equicord-launcher.iss')
if ($LASTEXITCODE -ne 0) { throw "ISCC a échoué (code $LASTEXITCODE)." }

Write-Host ">> Installeur : $(Join-Path $PSScriptRoot 'output\equicord-launcher-setup.exe')"
