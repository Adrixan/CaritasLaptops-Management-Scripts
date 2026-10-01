#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Platziert die Caritas Management-Suite auf den Desktops administrativer Konten.
.DESCRIPTION
    Kopiert die Caritas-Skriptsammlung von einem Bereitstellungsort (Standard: C:\ProgramData\CaritasScripts)
    auf den Desktop administrativer Benutzerkonten (CaritasAdmin, Administrator sowie lokale Administratoren)
    und richtet Verknüpfungen für GUI, Terminal und Handbuch ein.
.PARAMETER StagedPath
    Quellverzeichnis der bereitgestellten Skripte. Standard: 'C:\ProgramData\CaritasScripts'.
.PARAMETER TargetUsers
    Liste der Zielbenutzernamen. Standard: Automatische Ermittlung aller administrativen Konten.
.PARAMETER TargetUser
    Einzelner Zielbenutzername (für Rückwärtskompatibilität).
.PARAMETER AllAdmins
    Ermittelt und versorgt automatisch alle lokalen Administratorkonten.
.PARAMETER ForceSync
    Erzwingt das Überschreiben vorhandener Dateien auf dem Ziel-Desktop.
#>
[CmdletBinding()]
param(
    [string]$StagedPath = "C:\ProgramData\CaritasScripts",
    [string[]]$TargetUsers = @(),
    [string]$TargetUser = "",
    [switch]$AllAdmins,
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

# 2. Resolve Target Users
$deployList = [System.Collections.Generic.List[string]]::new()

if ($TargetUser) {
    $deployList.Add($TargetUser)
}
if ($TargetUsers -and $TargetUsers.Count -gt 0) {
    foreach ($tu in $TargetUsers) {
        if ($tu -and -not $deployList.Contains($tu)) {
            $deployList.Add($tu)
        }
    }
}

# If no target specified or AllAdmins requested, discover all administrative accounts
if ($deployList.Count -eq 0 -or $AllAdmins) {
    # 1. Standard Caritas Admin
    if (-not $deployList.Contains("CaritasAdmin")) { $deployList.Add("CaritasAdmin") }

    # 2. Built-in Administrator (RID -500 or localized name)
    try {
        $builtin = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -match '-500$' }
        if ($builtin -and -not $deployList.Contains($builtin.Name)) { $deployList.Add($builtin.Name) }
    } catch {}
    try {
        $cimAdmin = Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount=True AND SID LIKE '%-500'" -ErrorAction SilentlyContinue
        if ($cimAdmin -and $cimAdmin.Name -and -not $deployList.Contains($cimAdmin.Name)) { $deployList.Add($cimAdmin.Name) }
    } catch {}
    if (-not $deployList.Contains("Administrator")) { $deployList.Add("Administrator") }

    # 3. Members of local Administrators group (S-1-5-32-544)
    try {
        $adminGroup = Get-LocalGroup -SID "S-1-5-32-544" -ErrorAction SilentlyContinue
        if ($adminGroup) {
            $members = Get-LocalGroupMember -Group $adminGroup.Name -ErrorAction SilentlyContinue
            foreach ($m in $members) {
                $rawName = $m.Name.Split('\')[-1]
                if ($rawName -and -not $deployList.Contains($rawName)) {
                    $deployList.Add($rawName)
                }
            }
        }
    } catch {}

    # Net localgroup parsing fallback
    foreach ($grpCand in @("Administratoren", "Administrators")) {
        try {
            $netOut = & net.exe localgroup "$grpCand" 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) {
                $inMembers = $false
                foreach ($line in ($netOut -split "\r?\n")) {
                    if ($line -match "^---") { $inMembers = $true; continue }
                    if ($line -match "Befehl wurde erfolgreich|command completed") { $inMembers = $false; break }
                    if ($inMembers -and $line.Trim()) {
                        $acct = $line.Trim().Split('\')[-1]
                        if ($acct -and -not $deployList.Contains($acct)) {
                            $deployList.Add($acct)
                        }
                    }
                }
            }
        } catch {}
    }

    # 4. Currently logged in user if running interactively and user is in administrators
    if ($env:USERNAME -and $env:USERNAME -notin @("SYSTEM", "LOCAL SERVICE", "NETWORK SERVICE")) {
        if (-not $deployList.Contains($env:USERNAME)) {
            $deployList.Add($env:USERNAME)
        }
    }
}

# Filter out system and service accounts
$excludedAccounts = @("NT AUTHORITY\SYSTEM", "SYSTEM", "LOCAL SERVICE", "NETWORK SERVICE", "DefaultAccount", "WDAGUtilityAccount")
$finalTargetUsers = @($deployList | Where-Object { $_ -and $_ -notin $excludedAccounts } | Select-Object -Unique)

# 3. Resolve Source Suite Directory
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

Write-DeployLog "Starte Desktop-Bereitstellung für folgende Konten: $($finalTargetUsers -join ', ')..." "INFO" ([ConsoleColor]::Cyan)

foreach ($target in $finalTargetUsers) {
    Write-DeployLog "Prüfe Desktop-Bereitstellung für Administrator '$target'..." "INFO" ([ConsoleColor]::Yellow)
    $targetDesktop = $null

    # Method 1: If current caller is target user
    if ($env:USERNAME -eq $target) {
        $targetDesktop = [Environment]::GetFolderPath("Desktop")
        if (-not $targetDesktop) { $targetDesktop = Join-Path $env:USERPROFILE "Desktop" }
    }

    # Method 2: Lookup via Registry ProfileList
    if (-not $targetDesktop -or -not (Test-Path $targetDesktop)) {
        try {
            $userSid = $null
            $localUser = Get-LocalUser -Name $target -ErrorAction SilentlyContinue
            if ($localUser) {
                $userSid = $localUser.SID.Value
            } else {
                $cimUser = Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount=True AND Name='$target'" -ErrorAction SilentlyContinue
                if ($cimUser) { $userSid = $cimUser.SID }
            }
            if ($userSid) {
                $profRegKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$userSid"
                if (Test-Path $profRegKey) {
                    $profPath = (Get-ItemProperty -Path $profRegKey -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
                    if ($profPath -and (Test-Path $profPath)) {
                        $deskCand = Join-Path $profPath "Desktop"
                        if (-not (Test-Path $deskCand)) {
                            New-Item -ItemType Directory -Path $deskCand -Force -ErrorAction SilentlyContinue | Out-Null
                        }
                        if (Test-Path $deskCand) {
                            $targetDesktop = $deskCand
                        }
                    }
                }
            }
        } catch {}
    }

    # Method 3: Direct User Profile Folder Checks
    if (-not $targetDesktop -or -not (Test-Path $targetDesktop)) {
        $candidatePaths = @(
            "C:\Users\$target\Desktop",
            "C:\Users\$target.$env:COMPUTERNAME\Desktop"
        )
        foreach ($cp in $candidatePaths) {
            if (Test-Path $cp) {
                $targetDesktop = $cp
                break
            }
            $parent = Split-Path -Path $cp -Parent
            if (Test-Path $parent) {
                try {
                    New-Item -ItemType Directory -Path $cp -Force -ErrorAction SilentlyContinue | Out-Null
                    if (Test-Path $cp) {
                        $targetDesktop = $cp
                        break
                    }
                } catch {}
            }
        }
    }

    if (-not $targetDesktop -or -not (Test-Path $targetDesktop)) {
        Write-DeployLog "Desktop-Verzeichnis für '$target' existiert noch nicht (Benutzerprofil noch nicht initialisiert). Bereitstellung wird beim ersten Login ausgeführt." "INFO" ([ConsoleColor]::Gray)
        continue
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
            Write-DeployLog "Skriptsammlung erfolgreich auf den Desktop von '$target' kopiert." "ACTION" ([ConsoleColor]::Green)
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
            Write-DeployLog "Desktop-Verknüpfung 'Caritas Verwaltung.lnk' für '$target' erstellt." "ACTION" ([ConsoleColor]::Green)
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
            Write-DeployLog "Desktop-Verknüpfung 'Caritas Verwaltung (Terminal).lnk' für '$target' erstellt." "ACTION" ([ConsoleColor]::Green)
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
            Write-DeployLog "Desktop-Verknüpfung 'Caritas Handbuch.lnk' für '$target' erstellt." "ACTION" ([ConsoleColor]::Green)
        }
    } catch {
        Write-DeployLog "Warnung beim Erstellen der Desktop-Verknüpfungen für '$target': $_" "WARN" ([ConsoleColor]::Yellow)
    }

    # 6. Apply Permissions (Full Control for Administrators and TargetUser)
    try {
        & icacls.exe "$destSuiteDir" /grant "*S-1-5-32-544:(OI)(CI)F" /grant "${target}:(OI)(CI)F" /T /C /Q 2>$null | Out-Null
        & icacls.exe "$targetDesktop\Caritas*.lnk" /grant "*S-1-5-32-544:F" /grant "${target}:F" /Q 2>$null | Out-Null
    } catch {}

    Write-DeployLog "Bereitstellung auf dem Desktop von '$target' erfolgreich abgeschlossen." "DONE" ([ConsoleColor]::Green)
}

Write-DeployLog "Alle Desktop-Bereitstellungen für Administratoren abgeschlossen." "DONE" ([ConsoleColor]::Green)
