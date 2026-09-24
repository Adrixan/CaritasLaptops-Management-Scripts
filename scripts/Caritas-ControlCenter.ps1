#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Caritas Laptop Control Center - Interactive Terminal User Interface (TUI).
.DESCRIPTION
    Central administrative management console for Caritas laptops:
    - Provides single-key interactive menu for all operational maintenance routines.
    - Includes automated 1-click initial onboarding for newly donated laptops.
    - Checks for script updates from GitHub with fast-fail offline timeouts.
    - Allows seamless switching between Terminal (TUI) and Graphical (GUI) modes.
    - Automatically requests UAC elevation if launched without administrative tokens.
.NOTES
    Compatible with all Windows 11 editions (Home, Pro, Enterprise, Education).
    Logs operations to logs\ControlCenter.log.
#>
[CmdletBinding()]
param(
    [switch]$CheckUpdateOnly,
    [switch]$RunOnboardingUnattended
)

# Enforce UTF-8 console and pipeline encoding
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# 1. Enforce Elevated Privileges
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    exit
}

# 2. Environment & Directories (Dynamically Resolved)
$ErrorActionPreference = "Continue"

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Item -Path ".").FullName }

$baseDir = Split-Path -Path $scriptDir -Parent
if (-not (Test-Path "$baseDir\scripts")) {
    $baseDir = $scriptDir
}

$configDir = Join-Path $baseDir "config"
$logDir = Join-Path $baseDir "logs"
$stagingDir = Join-Path $env:TEMP "CaritasStaging"

foreach ($dir in @($scriptDir, $configDir, $logDir)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

$localVersionFile = Join-Path $baseDir "version.json"
if (-not (Test-Path $localVersionFile)) {
    $localVersionFile = Join-Path $configDir "version.json"
}
$logFile = Join-Path $logDir "ControlCenter.log"

try {
    $Host.UI.RawUI.WindowTitle = "Caritas Laptop Control Center - $env:COMPUTERNAME"
} catch {}

function Write-CCLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Get-LocalVersion {
    if (Test-Path $localVersionFile) {
        try {
            $v = Get-Content $localVersionFile -Raw | ConvertFrom-Json
            return $v.version
        } catch {}
    }
    return "1.0.0"
}

# 2. Fast-Fail Self-Update Check (2s Timeout)
function Check-ForUpdates {
    param([switch]$Interactive)
    $localVer = Get-LocalVersion
    $remoteVersionUrl = "https://raw.githubusercontent.com/Adrixan/CaritasLaptops-Management-Scripts/main/version.json"

    if ($Interactive) {
        Write-Host "Prüfe GitHub auf Skript-Aktualisierungen..." -ForegroundColor Cyan
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $remoteMeta = Invoke-RestMethod -Uri $remoteVersionUrl -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop

        if ($remoteMeta.version -and ($remoteMeta.version -ne $localVer)) {
            Write-Host "`n[UPDATE VERFÜGBAR] Version $($remoteMeta.version) ist verfügbar (Lokal: $localVer)!" -ForegroundColor Yellow
            Write-CCLog "Update available: local=$localVer, remote=$($remoteMeta.version)"
            if ($Interactive) {
                $ans = Read-Host "Möchten Sie die Skripte jetzt automatisch aktualisieren? (J/N)"
                if ($ans -eq "J" -or $ans -eq "j" -or $ans -eq "Y" -or $ans -eq "y") {
                    Invoke-SelfUpdate -ArchiveUrl $remoteMeta.archiveUrl -TargetVersion $remoteMeta.version
                }
            }
            return $true
        } else {
            if ($Interactive) {
                Write-Host "[OK] Alle Skripte sind auf dem neuesten Stand (Version $localVer)." -ForegroundColor Green
            }
            return $false
        }
    } catch {
        if ($Interactive) {
            Write-Host "Hinweis: Update-Server nicht erreichbar oder Gerät ist offline." -ForegroundColor DarkGray
        }
        Write-CCLog "Update check skipped/failed: $_" "WARN"
        return $false
    }
}

function Invoke-SelfUpdate {
    param(
        [string]$ArchiveUrl = "https://github.com/Adrixan/CaritasLaptops-Management-Scripts/archive/refs/heads/main.zip",
        [string]$TargetVersion = "Neu"
    )
    Write-Host "Lade Aktualisierungspaket herunter..." -ForegroundColor Cyan
    $stagingDir = Join-Path $env:TEMP "CaritasStaging"
    if (Test-Path $stagingDir) { Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
    $zipPath = Join-Path $stagingDir "update.zip"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $ArchiveUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 30
        Expand-Archive -Path $zipPath -DestinationPath $stagingDir -Force

        # Locate extracted scripts folder
        $extractedRoot = Get-ChildItem -Path $stagingDir -Directory | Select-Object -First 1
        $srcScripts = if ($extractedRoot -and (Test-Path "$($extractedRoot.FullName)\scripts")) {
            "$($extractedRoot.FullName)\scripts"
        } elseif (Test-Path "$stagingDir\scripts") {
            "$stagingDir\scripts"
        } elseif ($extractedRoot) {
            $extractedRoot.FullName
        } else {
            $stagingDir
        }
        $srcVersion = if ($extractedRoot -and (Test-Path "$($extractedRoot.FullName)\version.json")) {
            "$($extractedRoot.FullName)\version.json"
        } elseif (Test-Path "$stagingDir\version.json") {
            "$stagingDir\version.json"
        } else {
            $null
        }

        $psFiles = Get-ChildItem -Path $srcScripts -Filter "*.ps1" -ErrorAction SilentlyContinue
        if ($psFiles) {
            foreach ($f in $psFiles) {
                Copy-Item -Path $f.FullName -Destination $scriptDir -Force
            }
            if ($srcVersion -and (Test-Path $srcVersion)) { Copy-Item -Path $srcVersion -Destination $localVersionFile -Force }
            Write-Host "[ERFOLG] Skripte erfolgreich auf Version $TargetVersion aktualisiert!" -ForegroundColor Green
            Write-CCLog "Self-update successful to version $TargetVersion"
            Start-Sleep -Seconds 2
        }
    } catch {
        Write-Host "Fehler beim Aktualisieren: $_" -ForegroundColor Red
        Write-CCLog "Self-update failed: $_" "ERROR"
    } finally {
        if (Test-Path $stagingDir) { Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# 3. Master Onboarding Orchestration (All-in-One for New Laptops)
function Invoke-MasterOnboarding {
    param([switch]$Unattended)
    Clear-Host
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "   CARITAS LAPTOP ERST-EINRICHTUNG (ALL-IN-ONE SETUP)         " -ForegroundColor Green
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "Dieses Verfahren richtet ein neu gespendetes Gerät vollständig ein:"
    Write-Host "- Phase 1: Software-Bereinigung & Winget-Installation"
    Write-Host "- Phase 2: Windows Update, Firmware & Treiber"
    Write-Host "- Phase 3: Sicherheits-, Energie- & Hardening-Richtlinien"
    Write-Host "- Phase 4: Standard-Programme (Firefox, VLC, Office) & uBlock"
    Write-Host "- Phase 5: Browser-Datenschutz, USB-Sperre & Desktop-Hygiene"
    Write-Host "- Phase 6: Benutzerkonto 'User' & Sitzungs-Reset einrichten"
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not $Unattended) {
        $confirm = Read-Host "Möchten Sie die Erst-Einrichtung jetzt starten? (J/N)"
        if ($confirm -ne "J" -and $confirm -ne "j" -and $confirm -ne "Y" -and $confirm -ne "y") {
            Write-Host "Abgebrochen." -ForegroundColor Gray
            Start-Sleep -Seconds 1
            return
        }
    }

    $startTime = Get-Date
    Write-CCLog "Starting Master Onboarding routine"

    Write-Host "`n>>> [1/5] Synchronisiere Software & installiere Updates..." -ForegroundColor Yellow
    & "$scriptDir\Sync-CaritasSoftware.ps1"

    Write-Host "`n>>> [2/5] Wende System-Hardening & Energie-Richtlinien an..." -ForegroundColor Yellow
    & "$scriptDir\Configure-CaritasHardening.ps1"

    Write-Host "`n>>> [3/5] Richte Standard-Programme & Werbeblocker ein..." -ForegroundColor Yellow
    & "$scriptDir\Configure-CaritasDefaults.ps1"

    Write-Host "`n>>> [4/5] Richte Datenschutz, USB-Sperre & Speicher-Wartung ein..." -ForegroundColor Yellow
    & "$scriptDir\Configure-CaritasMaintenanceAndPrivacy.ps1"

    Write-Host "`n>>> [5/5] Richte Benutzerkonto 'User' & Clean Slate Reset ein..." -ForegroundColor Yellow
    & "$scriptDir\Reset-CaritasUserProfile.ps1" -InstallAll

    $duration = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
    Write-Host "`n==============================================================" -ForegroundColor Green
    Write-Host "  ERST-EINRICHTUNG ERFOLGREICH ABGESCHLOSSEN! (Dauer: $duration Min.)" -ForegroundColor Green
    Write-Host "==============================================================" -ForegroundColor Green
    Write-CCLog "Master Onboarding completed in $duration minutes"
    if (-not $Unattended) {
        Read-Host "Drücken Sie die Eingabetaste, um zum Hauptmenü zurückzukehren..."
    }
}

function Show-AuditLogs {
    Clear-Host
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "               CARITAS AUDIT LOG ÜBERSICHT                   " -ForegroundColor Yellow
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "Verfügbare Protokolle in $($logDir):"
    $logs = Get-ChildItem -Path $logDir -Filter "*.log" -ErrorAction SilentlyContinue
    if (-not $logs) {
        Write-Host "Keine Logdateien gefunden." -ForegroundColor Gray
    } else {
        $idx = 1
        foreach ($l in $logs) {
            $sizeKb = [Math]::Round($l.Length / 1KB, 1)
            Write-Host "  [$idx] $($l.Name) ($sizeKb KB - Zuletzt geändert: $($l.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))"
            $idx++
        }
        Write-Host "  [0] Zurück zum Hauptmenü"
        Write-Host ""
        $choice = Read-Host "Wählen Sie ein Log zum Anzeigen [0-$($logs.Count)]"
        $num = 0
        if ([int]::TryParse($choice, [ref]$num) -and $num -ge 1 -and $num -le $logs.Count) {
            $selected = $logs[$num - 1]
            Clear-Host
            Write-Host "=== Inhalt von $($selected.FullName) (Letzte 40 Zeilen) ===" -ForegroundColor Cyan
            Get-Content $selected.FullName -Tail 40 | Out-Host
            Write-Host "==============================================================" -ForegroundColor Cyan
            Read-Host "Drücken Sie die Eingabetaste, um fortzufahren..."
        }
    }
}

# 4. Main Menu Loop
if ($CheckUpdateOnly) {
    Check-ForUpdates -Interactive
    exit
}

if ($RunOnboardingUnattended) {
    Invoke-MasterOnboarding -Unattended
    exit
}

# Background check for updates quietly on startup
$updateFound = Check-ForUpdates

while ($true) {
    Clear-Host
    $curVer = Get-LocalVersion
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "         CARITAS LAPTOP CONTROL CENTER - v$curVer             " -ForegroundColor Yellow
    Write-Host "         Host: $env:COMPUTERNAME | Modus: Administrator       " -ForegroundColor Gray
    if ($updateFound) {
        Write-Host "         * HINWEIS: Ein Skript-Update ist verfügbar (Menü [9])" -ForegroundColor Red
    }
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Erst-Einrichtung (Vollständiges Onboarding neuer Geräte)" -ForegroundColor Green
    Write-Host "  [2] Vollständige Wartung (Software-Retention, Winget, Windows Update)"
    Write-Host "  [3] Schnelle Software-Wartung (Nur Winget & App-Retention)"
    Write-Host "  [4] Standard-Programme & Werbeblocker (Firefox, VLC, uBlock)"
    Write-Host "  [5] Sicherheits- & Energie-Richtlinien (Hardening, kein Standby)"
    Write-Host "  [6] Wartungs-, Datenschutz- & USB-Sperre (Passwörter, USB-Hygiene)"
    Write-Host "  [7] Benutzerkonto 'User' komplett zurücksetzen (Clean Slate)" -ForegroundColor Yellow
    Write-Host "  [8] Grafische Benutzeroberfläche (GUI) öffnen" -ForegroundColor Cyan
    Write-Host "  [9] Nach Skript-Updates suchen"
    Write-Host "  [L] Audit-Logs anzeigen"
    Write-Host "  [0] Beenden"
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Cyan
    $selection = Read-Host "Bitte wählen Sie eine Option [0-9, L]"

    switch ($selection.ToUpper()) {
        "1" { Invoke-MasterOnboarding }
        "2" {
            Clear-Host
            Write-Host "Starte vollständige Software- und System-Wartung..." -ForegroundColor Yellow
            & "$scriptDir\Sync-CaritasSoftware.ps1"
            Read-Host "`nWartung abgeschlossen. Eingabetaste zum Fortfahren..."
        }
        "3" {
            Clear-Host
            Write-Host "Starte schnelle Software-Wartung (ohne Windows Update)..." -ForegroundColor Yellow
            & "$scriptDir\Sync-CaritasSoftware.ps1" -SkipWindowsUpdate
            Read-Host "`nSoftware-Wartung abgeschlossen. Eingabetaste zum Fortfahren..."
        }
        "4" {
            Clear-Host
            Write-Host "Richte Standard-Programme und uBlock Origin ein..." -ForegroundColor Yellow
            & "$scriptDir\Configure-CaritasDefaults.ps1"
            Read-Host "`nStandard-Programme eingerichtet. Eingabetaste zum Fortfahren..."
        }
        "5" {
            Clear-Host
            Write-Host "Wende Sicherheits- und Energie-Richtlinien an..." -ForegroundColor Yellow
            & "$scriptDir\Configure-CaritasHardening.ps1"
            Read-Host "`nSicherheits-Richtlinien angewendet. Eingabetaste zum Fortfahren..."
        }
        "6" {
            Clear-Host
            Write-Host "Wende Datenschutz-, USB- und Wartungs-Richtlinien an..." -ForegroundColor Yellow
            & "$scriptDir\Configure-CaritasMaintenanceAndPrivacy.ps1"
            Read-Host "`nDatenschutz-Richtlinien angewendet. Eingabetaste zum Fortfahren..."
        }
        "7" {
            Clear-Host
            Write-Host "Setze Benutzerkonto 'User' auf den Ausgangszustand zurück..." -ForegroundColor Yellow
            & "$scriptDir\Reset-CaritasUserProfile.ps1" -TargetUsername "User"
            Read-Host "`nBenutzer zurückgesetzt. Eingabetaste zum Fortfahren..."
        }
        "8" {
            $guiScript = "$scriptDir\Caritas-ControlCenter-GUI.ps1"
            if (Test-Path $guiScript) {
                Write-Host "Starte grafische Benutzeroberfläche..." -ForegroundColor Cyan
                Start-Process powershell.exe -ArgumentList @('-Sta', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $guiScript)
                exit
            } else {
                Write-Host "GUI-Skript ($guiScript) nicht gefunden." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
        "9" {
            Check-ForUpdates -Interactive
            Read-Host "Eingabetaste zum Fortfahren..."
        }
        "L" { Show-AuditLogs }
        "0" {
            Write-Host "Beenden..." -ForegroundColor Gray
            exit
        }
        Default {
            Write-Host "Ungültige Auswahl. Bitte wählen Sie 0 bis 9." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
