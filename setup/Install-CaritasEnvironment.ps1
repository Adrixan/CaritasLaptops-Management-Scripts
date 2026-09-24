#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Caritas Laptop Environment & Shortcut Provisioner.
.DESCRIPTION
    Initializes the local Caritas Laptop Management Suite in place:
    - Resolves location dynamically (e.g. from Desktop, Downloads, or cloned repo).
    - Creates local subdirectories (config, logs) without polluting C:\.
    - Creates elevated desktop shortcuts on administrator profiles pointing to the local launchers.
    - Optionally starts the Control Center immediately.
#>
[CmdletBinding()]
param(
    [switch]$LaunchControlCenter,
    [switch]$TerminalOnly
)

$ErrorActionPreference = "Stop"

# Enforce UTF-8 console and pipeline encoding
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# 1. Enforce Administrator
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "UAC-Erhöhung erforderlich. Starte PowerShell als Administrator..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    exit
}

# 2. Dynamically Resolve Suite Root
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Item -Path ".").FullName }

$baseDir = Split-Path -Path $scriptDir -Parent
if (-not (Test-Path "$baseDir\scripts")) {
    $baseDir = $scriptDir
}

$targetLogs = Join-Path $baseDir "logs"
$targetConfig = Join-Path $baseDir "config"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "     CARITAS LAPTOP ENVIRONMENT INITIALISIERUNG              " -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "Basispfad: $baseDir" -ForegroundColor Gray

# 3. Create Local Directories
foreach ($dir in @($targetLogs, $targetConfig)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "[+] Verzeichnis erstellt: $dir" -ForegroundColor Gray
    }
}

# 4. Locate Launchers
$guiLauncher = if (Test-Path "$baseDir\Caritas-Verwaltung.cmd") {
    "$baseDir\Caritas-Verwaltung.cmd"
} elseif (Test-Path "$baseDir\setup\Caritas-Verwaltung.cmd") {
    "$baseDir\setup\Caritas-Verwaltung.cmd"
} else {
    "$baseDir\scripts\Caritas-ControlCenter-GUI.ps1"
}

$tuiLauncher = if (Test-Path "$baseDir\Caritas-Verwaltung-TUI.cmd") {
    "$baseDir\Caritas-Verwaltung-TUI.cmd"
} elseif (Test-Path "$baseDir\setup\Caritas-Verwaltung-TUI.cmd") {
    "$baseDir\setup\Caritas-Verwaltung-TUI.cmd"
} else {
    "$baseDir\scripts\Caritas-ControlCenter.ps1"
}

# 5. Deploy Desktop Shortcuts to Active Administrator Profiles
$wsh = New-Object -ComObject WScript.Shell

$adminGroupMembers = (Get-LocalGroupMember -Group (Get-LocalGroup -SID 'S-1-5-32-544').Name -ErrorAction SilentlyContinue).Name | ForEach-Object { ($_ -split '\\')[-1] }
$activeAdminNames = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -and ($_.Name -in $adminGroupMembers) } | Select-Object -ExpandProperty Name

$adminProfiles = @()
# Include current caller desktop
$currentDesktop = [Environment]::GetFolderPath("Desktop")
if ($currentDesktop -and (Test-Path $currentDesktop)) {
    $adminProfiles += $currentDesktop
}

$userProfiles = Get-ChildItem -Path "C:\Users" -Directory | Where-Object { $_.Name -in $activeAdminNames }
foreach ($p in $userProfiles) {
    $desktopPath = Join-Path $p.FullName "Desktop"
    if ((Test-Path $desktopPath) -and ($desktopPath -notin $adminProfiles)) {
        $adminProfiles += $desktopPath
    }
}

foreach ($dPath in $adminProfiles) {
    try {
        # GUI Shortcut
        $guiLnkPath = Join-Path $dPath "Caritas Verwaltung.lnk"
        $lnkGui = $wsh.CreateShortcut($guiLnkPath)
        $lnkGui.TargetPath = $guiLauncher
        $lnkGui.WorkingDirectory = $baseDir
        $lnkGui.Description = "Caritas Laptop Kontrollzentrum (Grafische Verwaltungsoberfläche)"
        $lnkGui.IconLocation = "$env:SystemRoot\System32\shell32.dll,277"
        $lnkGui.Save()
        Write-Host "[+] Desktop-Verknüpfung erstellt: $guiLnkPath" -ForegroundColor Green

        # Terminal Shortcut
        $tuiLnkPath = Join-Path $dPath "Caritas Verwaltung (Terminal).lnk"
        $lnkTui = $wsh.CreateShortcut($tuiLnkPath)
        $lnkTui.TargetPath = $tuiLauncher
        $lnkTui.WorkingDirectory = $baseDir
        $lnkTui.Description = "Caritas Laptop Kontrollzentrum (Terminal-Modus)"
        $lnkTui.IconLocation = "$env:SystemRoot\System32\powershell.exe,0"
        $lnkTui.Save()
        Write-Host "[+] Desktop-Verknüpfung erstellt: $tuiLnkPath" -ForegroundColor Green
    } catch {
        Write-Host "[-] Fehler beim Erstellen der Verknüpfung in $($dPath): $_" -ForegroundColor Yellow
    }
}

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  INITIALISIERUNG ERFOLGREICH ABGESCHLOSSEN!" -ForegroundColor Green
Write-Host "  Die Verwaltungswerkzeuge sind einsatzbereit." -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Cyan

if ($LaunchControlCenter) {
    if ($TerminalOnly) {
        Start-Process cmd.exe -ArgumentList "/c `"$tuiLauncher`""
    } else {
        Start-Process cmd.exe -ArgumentList "/c `"$guiLauncher`""
    }
}
