#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Platziert die Caritas Management-Suite auf dem Desktop von CaritasAdmin.
.DESCRIPTION
    Kopiert die Caritas-Skriptsammlung von einem Bereitstellungsort (Standard: C:\ProgramData\CaritasScripts)
    auf den Desktop des lokalen Administrators 'CaritasAdmin' (C:\Users\CaritasAdmin\Desktop\CaritasScripts)
    und richtet Verknüpfungen für GUI, Terminal und Handbuch ein.
.PARAMETER StagedPath
    Quellverzeichnis der bereitgestellten Skripte. Standard: 'C:\ProgramData\CaritasScripts'.
.PARAMETER TargetUser
    Zielbenutzername. Standard: 'CaritasAdmin'.
.PARAMETER ForceSync
    Erzwingt das Überschreiben vorhandener Dateien auf dem Ziel-Desktop.
#>
[CmdletBinding()]
param(
    [string]$StagedPath = "C:\ProgramData\CaritasScripts",
    [string]$TargetUser = "CaritasAdmin",
    [switch]$ForceSync
)

$ErrorActionPreference = "Continue"

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# 1. Logging Helper
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Item -Path ".").FullName }
$baseDir = Split-Path -Path $scriptDir -Parent

function Write-DeployLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$timestamp] [DESKTOP-DEPLOY] [$Level] $Message"
    Write-Host $logLine -ForegroundColor $Color

    $logTargets = @(
        (Join-Path $StagedPath "logs\AdminAccounts.log"),
        (Join-Path $baseDir "logs\AdminAccounts.log")
    )
    foreach ($lt in $logTargets) {
        try {
            $dir = Split-Path -Path $lt -Parent
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Add-Content -Path $lt -Value $logLine -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch {}
    }
}

Write-DeployLog "Prüfe Desktop-Bereitstellung der Caritas Management-Suite für '$TargetUser'..." "INFO" ([ConsoleColor]::Yellow)

# 2. Resolve Source Suite Directory
$resolvedSource = $null
if (Test-Path (Join-Path $StagedPath "Caritas-Verwaltung.cmd")) {
    $resolvedSource = $StagedPath
} elseif (Test-Path (Join-Path $baseDir "Caritas-Verwaltung.cmd")) {
    $resolvedSource = $baseDir
}

if (-not $resolvedSource) {
    Write-DeployLog "Keine gültige Skriptsammlung unter '$StagedPath' oder '$baseDir' gefunden." "WARN" ([ConsoleColor]::Yellow)
    return
}

# 3. Resolve Target Desktop Directory for TargetUser
$targetDesktop = $null

if ($env:USERNAME -eq $TargetUser) {
    $targetDesktop = [Environment]::GetFolderPath("Desktop")
    if (-not $targetDesktop) { $targetDesktop = Join-Path $env:USERPROFILE "Desktop" }
}

if (-not $targetDesktop -or -not (Test-Path $targetDesktop)) {
    try {
        $localUser = Get-LocalUser -Name $TargetUser -ErrorAction SilentlyContinue
        if ($localUser) {
            $userSid = $localUser.SID.Value
            $profRegKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$userSid"
            if (Test-Path $profRegKey) {
                $profPath = (Get-ItemProperty -Path $profRegKey -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
                if ($profPath -and (Test-Path $profPath)) {
                    $targetDesktop = Join-Path $profPath "Desktop"
                }
            }
        }
    } catch {}

    if (-not $targetDesktop) {
        $candidatePath = "C:\Users\$TargetUser\Desktop"
        if (Test-Path $candidatePath) {
            $targetDesktop = $candidatePath
        }
    }
}

# If user profile directory exists but Desktop folder is still being initialized (first logon)
if (-not $targetDesktop -or -not (Test-Path $targetDesktop)) {
    $userProfBase = "C:\Users\$TargetUser"
    if (Test-Path $userProfBase) {
        $waitCount = 0
        while (-not (Test-Path "$userProfBase\Desktop") -and ($waitCount -lt 15)) {
            Start-Sleep -Seconds 1
            $waitCount++
        }
        if (Test-Path "$userProfBase\Desktop") {
            $targetDesktop = "$userProfBase\Desktop"
        }
    }
}

if (-not $targetDesktop -or -not (Test-Path $targetDesktop)) {
    Write-DeployLog "Desktop-Verzeichnis für '$TargetUser' existiert noch nicht (Benutzerprofil wurde noch nicht angemeldet). Bereitstellung wird beim ersten Login ausgeführt." "INFO" ([ConsoleColor]::Gray)
    return
}

# 4. Copy/Sync CaritasScripts Folder to Target Desktop
$destSuiteDir = Join-Path $targetDesktop "CaritasScripts"
$needsCopy = $ForceSync -or (-not (Test-Path $destSuiteDir)) -or (-not (Test-Path (Join-Path $destSuiteDir "Caritas-Verwaltung.cmd")))

if ($needsCopy) {
    Write-DeployLog "Kopiere Skriptsammlung nach '$destSuiteDir'..." "ACTION" ([ConsoleColor]::Cyan)
    try {
        if (-not (Test-Path $destSuiteDir)) {
            New-Item -ItemType Directory -Path $destSuiteDir -Force | Out-Null
        }
        Copy-Item -Path "$resolvedSource\*" -Destination $destSuiteDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-DeployLog "Skriptsammlung erfolgreich auf den Desktop von '$TargetUser' kopiert." "ACTION" ([ConsoleColor]::Green)
    } catch {
        Write-DeployLog "Fehler beim Kopieren der Skripte nach '$destSuiteDir': $_" "ERROR" ([ConsoleColor]::Red)
    }
} else {
    Write-DeployLog "Skriptsammlung ist unter '$destSuiteDir' bereits vorhanden." "INFO" ([ConsoleColor]::Green)
}

# 5. Create Desktop Shortcuts on Target Desktop
try {
    $wsh = New-Object -ComObject WScript.Shell

    # GUI Launcher Shortcut
    $guiLnkPath = Join-Path $targetDesktop "Caritas Verwaltung.lnk"
    $guiTarget = Join-Path $destSuiteDir "Caritas-Verwaltung.cmd"
    if (Test-Path $guiTarget) {
        $lnkGui = $wsh.CreateShortcut($guiLnkPath)
        $lnkGui.TargetPath = $guiTarget
        $lnkGui.WorkingDirectory = $destSuiteDir
        $lnkGui.Description = "Caritas Laptop Kontrollzentrum (Grafische Verwaltungsoberfläche)"
        $lnkGui.IconLocation = "$env:SystemRoot\System32\shell32.dll,277"
        $lnkGui.Save()
        Write-DeployLog "Desktop-Verknüpfung 'Caritas Verwaltung.lnk' erstellt." "ACTION" ([ConsoleColor]::Green)
    }

    # Terminal Launcher Shortcut
    $tuiLnkPath = Join-Path $targetDesktop "Caritas Verwaltung (Terminal).lnk"
    $tuiTarget = Join-Path $destSuiteDir "Caritas-Verwaltung-TUI.cmd"
    if (Test-Path $tuiTarget) {
        $lnkTui = $wsh.CreateShortcut($tuiLnkPath)
        $lnkTui.TargetPath = $tuiTarget
        $lnkTui.WorkingDirectory = $destSuiteDir
        $lnkTui.Description = "Caritas Laptop Kontrollzentrum (Terminal-Modus)"
        $lnkTui.IconLocation = "$env:SystemRoot\System32\powershell.exe,0"
        $lnkTui.Save()
        Write-DeployLog "Desktop-Verknüpfung 'Caritas Verwaltung (Terminal).lnk' erstellt." "ACTION" ([ConsoleColor]::Green)
    }

    # Handbuch PDF Shortcut
    $handbuchPdf = Join-Path $destSuiteDir "HANDBUCH.pdf"
    if (Test-Path $handbuchPdf) {
        $pdfLnkPath = Join-Path $targetDesktop "Caritas Handbuch.lnk"
        $lnkPdf = $wsh.CreateShortcut($pdfLnkPath)
        $lnkPdf.TargetPath = $handbuchPdf
        $lnkPdf.WorkingDirectory = $destSuiteDir
        $lnkPdf.Description = "Caritas Laptops Installations- und Betriebshandbuch"
        $lnkPdf.IconLocation = "$env:SystemRoot\System32\shell32.dll,264"
        $lnkPdf.Save()
        Write-DeployLog "Desktop-Verknüpfung 'Caritas Handbuch.lnk' erstellt." "ACTION" ([ConsoleColor]::Green)
    }
} catch {
    Write-DeployLog "Warnung beim Erstellen der Desktop-Verknüpfungen: $_" "WARN" ([ConsoleColor]::Yellow)
}

# 6. Apply Permissions (Full Control for Administrators and TargetUser)
try {
    & icacls.exe "$destSuiteDir" /grant "*S-1-5-32-544:(OI)(CI)F" /grant "$($TargetUser):(OI)(CI)F" /T /C /Q 2>$null | Out-Null
} catch {}

Write-DeployLog "Bereitstellung auf dem Desktop von '$TargetUser' abgeschlossen." "DONE" ([ConsoleColor]::Green)
