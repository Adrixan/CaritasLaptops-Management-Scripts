#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Caritas Laptop Environment Installer & Shortcut Provisioner.
.DESCRIPTION
    Installs the Caritas Laptop Management Suite to C:\Caritas\:
    - Sets up directory structure (Scripts, Config, Logs, Setup).
    - Copies script suite, configuration files, and batch launchers.
    - Creates elevated desktop shortcuts on administrator profiles.
    - Optionally registers system tasks and starts the Control Center.
#>
[CmdletBinding()]
param(
    [switch]$LaunchControlCenter,
    [switch]$TerminalOnly
)

$ErrorActionPreference = "Stop"

# 1. Enforce Administrator
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "UAC-Erhöhung erforderlich. Starte PowerShell als Administrator..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$sourceRoot = Split-Path -Path $PSScriptRoot -Parent
if (-not (Test-Path "$sourceRoot\scripts")) {
    $sourceRoot = $PSScriptRoot
}

$targetBase = "C:\Caritas"
$targetScripts = "$targetBase\Scripts"
$targetConfig = "$targetBase\Config"
$targetLogs = "$targetBase\Logs"
$targetSetup = "$targetBase\Setup"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "     CARITAS LAPTOP ENVIRONMENT INITIALISIERUNG              " -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Cyan

# 2. Directory Creation
foreach ($dir in @($targetScripts, $targetConfig, $targetLogs, $targetSetup)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "[+] Verzeichnis erstellt: $dir" -ForegroundColor Gray
    }
}

# 3. Copy Script Suite
$sourceScripts = if (Test-Path "$sourceRoot\scripts") { "$sourceRoot\scripts" } else { "$sourceRoot" }
if ($sourceScripts -ne $targetScripts) {
    $psFiles = Get-ChildItem -Path $sourceScripts -Filter "*.ps1" -ErrorAction SilentlyContinue
    foreach ($f in $psFiles) {
        Copy-Item -Path $f.FullName -Destination $targetScripts -Force
        Write-Host "[+] Skript kopiert: $($f.Name)" -ForegroundColor Gray
    }
} else {
    Write-Host "[*] Skripte bereits in $targetScripts vorhanden." -ForegroundColor Gray
}

# 4. Copy Setup & Launchers
$sourceSetup = if (Test-Path "$sourceRoot\setup") { "$sourceRoot\setup" } else { "$sourceRoot" }
if ($sourceSetup -ne $targetSetup) {
    $cmdFiles = Get-ChildItem -Path $sourceSetup -Filter "*.cmd" -ErrorAction SilentlyContinue
    foreach ($f in $cmdFiles) {
        Copy-Item -Path $f.FullName -Destination $targetSetup -Force
        Write-Host "[+] Launcher kopiert: $($f.Name)" -ForegroundColor Gray
    }
} else {
    Write-Host "[*] Setup-Dateien bereits in $targetSetup vorhanden." -ForegroundColor Gray
}

# 5. Copy Configuration & Version Metadata
$verFile = if (Test-Path "$sourceRoot\version.json") { "$sourceRoot\version.json" } else { "$sourceRoot\Config\version.json" }
$targetVer = "$targetConfig\version.json"
if ((Test-Path $verFile) -and ($verFile -ne $targetVer)) {
    Copy-Item -Path $verFile -Destination $targetConfig -Force
    Write-Host "[+] Konfiguration kopiert: version.json" -ForegroundColor Gray
}

# 6. Deploy Desktop Shortcuts to Administrator Profiles
$wsh = New-Object -ComObject WScript.Shell

$adminProfiles = @()
$userProfiles = Get-ChildItem -Path "C:\Users" -Directory | Where-Object { $_.Name -notin @("Default", "Default User", "All Users", "Public") }
foreach ($p in $userProfiles) {
    $desktopPath = Join-Path $p.FullName "Desktop"
    if (Test-Path $desktopPath) {
        $adminProfiles += $desktopPath
    }
}

# Primary GUI Shortcut
$guiLauncher = "$targetSetup\Caritas-Verwaltung.cmd"
$tuiLauncher = "$targetSetup\Caritas-Verwaltung-TUI.cmd"

foreach ($dPath in $adminProfiles) {
    try {
        # GUI Shortcut
        $guiLnkPath = Join-Path $dPath "Caritas Verwaltung.lnk"
        $lnkGui = $wsh.CreateShortcut($guiLnkPath)
        $lnkGui.TargetPath = $guiLauncher
        $lnkGui.WorkingDirectory = $targetSetup
        $lnkGui.Description = "Caritas Laptop Kontrollzentrum (Grafische Verwaltungsoberfläche)"
        $lnkGui.IconLocation = "$env:SystemRoot\System32\shell32.dll,277"
        $lnkGui.Save()
        Write-Host "[+] Desktop-Verknüpfung erstellt: $guiLnkPath" -ForegroundColor Green

        # Terminal Shortcut
        $tuiLnkPath = Join-Path $dPath "Caritas Verwaltung (Terminal).lnk"
        $lnkTui = $wsh.CreateShortcut($tuiLnkPath)
        $lnkTui.TargetPath = $tuiLauncher
        $lnkTui.WorkingDirectory = $targetSetup
        $lnkTui.Description = "Caritas Laptop Kontrollzentrum (Terminal-Modus)"
        $lnkTui.IconLocation = "$env:SystemRoot\System32\powershell.exe,0"
        $lnkTui.Save()
        Write-Host "[+] Desktop-Verknüpfung erstellt: $tuiLnkPath" -ForegroundColor Green
    } catch {
        Write-Host "[-] Fehler beim Erstellen der Verknüpfung in $($dPath): $_" -ForegroundColor Yellow
    }
}

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  INSTALLATION ERFOLGREICH ABGESCHLOSSEN!" -ForegroundColor Green
Write-Host "  Desktop-Verknüpfungen 'Caritas Verwaltung' sind einsatzbereit." -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Cyan

if ($LaunchControlCenter) {
    if ($TerminalOnly) {
        Start-Process powershell.exe -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$targetScripts\Caritas-ControlCenter.ps1`""
    } else {
        Start-Process powershell.exe -ArgumentList "-Sta -NoProfile -ExecutionPolicy Bypass -File `"$targetScripts\Caritas-ControlCenter-GUI.ps1`""
    }
}
