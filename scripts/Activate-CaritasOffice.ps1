#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Microsoft Office 2024 LTSC Lizenzpruefung und Aktivierung.
.DESCRIPTION
    Prueft, hinterlegt und aktiviert Microsoft Office 2024 LTSC Volumenlizenzen ueber ospp.vbs.
    Unterstuetzt sowohl manuelle interaktive Eingabe als auch automatisierte Uebergabe per Parameter.
.PARAMETER OfficeProductKey
    Optionaler 25-stelliger Microsoft Office Volumenlizenz MAK-Produktschluessel (mit oder ohne Bindestriche).
.PARAMETER CheckOnly
    Prueft und meldet lediglich den aktuellen Lizenzstatus ohne Aenderungen vorzunehmen.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OfficeProductKey = "",
    [switch]$CheckOnly
)

# Enforce UTF-8 console and pipeline encoding
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Continue"

Write-Host "PROGRESS: 10% - Suche Office-Installation..." -ForegroundColor Cyan

$osppCandidates = @(
    "$env:ProgramFiles\Microsoft Office\Office16\ospp.vbs",
    "${env:ProgramFiles(x86)}\Microsoft Office\Office16\ospp.vbs"
)
$ospp = $osppCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $ospp) {
    Write-Host "[-] Microsoft Office 16/2024 wurde auf diesem System nicht gefunden (ospp.vbs fehlt)." -ForegroundColor Yellow
    Write-Host "[WARN] Microsoft Office ist nicht installiert." -ForegroundColor Yellow
    exit 0
}

Write-Host "PROGRESS: 30% - Pruefe aktuellen Lizenzstatus..." -ForegroundColor Cyan
$statusOut = & cscript.exe //Nologo "$ospp" /dstatus 2>&1 | Out-String

if ($statusOut -match "---LICENSED---") {
    Write-Host "PROGRESS: 100% - Lizenzpruefung abgeschlossen" -ForegroundColor Green
    Write-Host "[OK] Microsoft Office ist bereits lizenziert und aktiviert." -ForegroundColor Green
    exit 0
}

if ($CheckOnly) {
    Write-Host "PROGRESS: 100% - Lizenzpruefung abgeschlossen" -ForegroundColor Yellow
    Write-Host "[WARN] Microsoft Office ist noch nicht lizenziert." -ForegroundColor Yellow
    exit 0
}

$cleanKey = ($OfficeProductKey -replace '[\s-]', '').Trim().ToUpper()
if (-not $cleanKey) {
    Write-Host "PROGRESS: 100% - Keine Lizenzschluessel-Eingabe" -ForegroundColor Yellow
    Write-Host "[WARN] Office ist nicht lizenziert. Kein Produktschluessel uebergeben." -ForegroundColor Yellow
    exit 0
}

if ($cleanKey.Length -ne 25) {
    Write-Host "[-] Der angegebene Produktschluessel hat nicht genau 25 Zeichen (ohne Bindestriche)." -ForegroundColor Red
    Write-Host "[FEHLER] Ungueltiges Schluesselformat (25 Zeichen erforderlich)." -ForegroundColor Red
    exit 1
}

# Re-format with standard 5x5 blocks (XXXXX-XXXXX-XXXXX-XXXXX-XXXXX)
$formattedKey = ($cleanKey -replace '(.{5})(?!$)', '$1-')

Write-Host "PROGRESS: 50% - Installiere Produktschluessel..." -ForegroundColor Cyan
Write-Host "[ACTION] Hinterlege MAK-Lizenzschluessel..." -ForegroundColor Yellow
$inpResult = & cscript.exe //Nologo "$ospp" "/inpkey:$formattedKey" 2>&1 | Out-String

Write-Host "PROGRESS: 75% - Aktiviere Office online..." -ForegroundColor Cyan
Write-Host "[ACTION] Sende Online-Aktivierungsanfrage an Microsoft..." -ForegroundColor Yellow
$actResult = & cscript.exe //Nologo "$ospp" /act 2>&1 | Out-String

Write-Host "PROGRESS: 90% - Verifiziere Aktivierung..." -ForegroundColor Cyan
$verifyOut = & cscript.exe //Nologo "$ospp" /dstatus 2>&1 | Out-String

if ($verifyOut -match "---LICENSED---") {
    Write-Host "PROGRESS: 100% - Aktivierung erfolgreich" -ForegroundColor Green
    Write-Host "[OK] Microsoft Office wurde erfolgreich aktiviert!" -ForegroundColor Green
} else {
    Write-Host "[-] Office-Aktivierung konnte nicht unmittelbar bestaetigt werden." -ForegroundColor Yellow
    Write-Host "[WARN] Microsoft Office Aktivierung ausstehend oder fehlgeschlagen." -ForegroundColor Yellow
    if ($actResult) {
        Write-Host $actResult -ForegroundColor Gray
    }
}
