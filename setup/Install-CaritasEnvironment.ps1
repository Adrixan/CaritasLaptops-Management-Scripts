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

# 6. Uninstall Discord & Discord System Helper
Write-Host "[*] Bereinige Discord und Discord System Helper..." -ForegroundColor Cyan
try {
    # 6.1 Terminate active Discord processes
    Get-Process -Name "*discord*", "*DiscordSystemHelper*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500

    # 6.2 Remove machine-wide Run keys (Squirrel autostart on every user logon)
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" -Name "Discord" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "Discord" -ErrorAction SilentlyContinue

    # 6.3 Remove machine-wide Squirrel installer files
    if (Test-Path "C:\ProgramData\SquirrelMachineInstalls\Discord.exe") {
        Remove-Item -Path "C:\ProgramData\SquirrelMachineInstalls\Discord.exe" -Force -ErrorAction SilentlyContinue
    }
    if ((Test-Path "C:\ProgramData\SquirrelMachineInstalls") -and ((Get-ChildItem "C:\ProgramData\SquirrelMachineInstalls" -ErrorAction SilentlyContinue).Count -eq 0)) {
        Remove-Item -Path "C:\ProgramData\SquirrelMachineInstalls" -Force -Recurse -ErrorAction SilentlyContinue
    }

    # 6.4 Clean per-user Run keys and Uninstall entries across all loaded hives
    Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | ForEach-Object {
        $sid = $_.PSChildName
        $runKey = "Registry::HKEY_USERS\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        if (Test-Path $runKey) {
            Remove-ItemProperty -Path $runKey -Name "Discord" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $runKey -Name "DiscordSystemHelper" -ErrorAction SilentlyContinue
        }
        $uninstKey = "Registry::HKEY_USERS\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Discord"
        if (Test-Path $uninstKey) {
            Remove-Item -Path $uninstKey -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 6.5 Execute native per-user uninstaller if present
    Get-ChildItem -Path "C:\Users\*\AppData\Local\Discord\Update.exe" -ErrorAction SilentlyContinue | ForEach-Object {
        Start-Process -FilePath $_.FullName -ArgumentList "--uninstall", "-s" -Wait -NoNewWindow -ErrorAction SilentlyContinue
    }

    # 6.6 Uninstall via winget if registered
    $winget = (Get-Command "winget" -ErrorAction SilentlyContinue).Source
    if (-not $winget) {
        $winget = (Get-ChildItem "C:\Users\*\AppData\Local\Microsoft\WindowsApps\winget.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    }
    if ($winget -and (Test-Path $winget)) {
        & $winget uninstall --id "XPDC2RH70K22MN" --silent --accept-source-agreements 2>$null | Out-Null
        & $winget uninstall --id "Discord.Discord" --silent --accept-source-agreements 2>$null | Out-Null
    }

    # 6.7 Kill any remaining processes and wipe directories and shortcuts
    Get-Process -Name "*discord*", "*DiscordSystemHelper*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "C:\Users\*\AppData\Local\Discord*" -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "C:\Users\*\AppData\Roaming\*discord*" -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "C:\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\*discord*" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\*discord*" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "C:\Users\*\Desktop\*discord*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "C:\Users\Public\Desktop\*discord*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    Write-Host "[+] Discord und Discord System Helper erfolgreich deinstalliert und bereinigt." -ForegroundColor Green
} catch {
    Write-Host "[-] Warnung bei der Discord-Bereinigung: $_" -ForegroundColor Yellow
}

# 7. Configure Automatic Logon for Standard Account 'User'
Write-Host "[*] Konfiguriere Benutzerkonto 'User' und automatische Anmeldung (Autologon)..." -ForegroundColor Cyan
try {
    $targetUsername = "User"
    $targetPass = "Caritas2412!"
    $secPass = ConvertTo-SecureString $targetPass -AsPlainText -Force

    $localUser = Get-LocalUser -Name $targetUsername -ErrorAction SilentlyContinue
    if (-not $localUser) {
        New-LocalUser -Name $targetUsername -Description "Standard-Gastkonto" -Password $secPass -ErrorAction SilentlyContinue | Out-Null
    } else {
        Set-LocalUser -Name $targetUsername -Password $secPass -ErrorAction SilentlyContinue | Out-Null
    }
    Set-LocalUser -Name $targetUsername -PasswordNeverExpires $true -UserMayChangePassword $true -ErrorAction SilentlyContinue | Out-Null
    $usersGroupName = (Get-LocalGroup | Where-Object { $_.SID.Value -eq "S-1-5-32-545" }).Name
    Add-LocalGroupMember -Group $usersGroupName -Member $targetUsername -ErrorAction SilentlyContinue

    $winlogonKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $winlogonKey -Name "AutoAdminLogon" -Value "1" -Type String -Force
    Set-ItemProperty -Path $winlogonKey -Name "DefaultUserName" -Value $targetUsername -Type String -Force
    Set-ItemProperty -Path $winlogonKey -Name "DefaultDomainName" -Value $env:COMPUTERNAME -Type String -Force
    Set-ItemProperty -Path $winlogonKey -Name "DefaultPassword" -Value $targetPass -Type String -Force
    Remove-ItemProperty -Path $winlogonKey -Name "ForceAutoLogon" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $winlogonKey -Name "LastUsedUsername" -Value $targetUsername -Type String -Force
    Remove-ItemProperty -Path $winlogonKey -Name "AutoLogonCount" -ErrorAction SilentlyContinue
    Write-Host "[+] Automatische Windows-Anmeldung für 'User' mit Kennwort aktiviert." -ForegroundColor Green
} catch {
    Write-Host "[-] Fehler beim Konfigurieren der automatischen Anmeldung: $_" -ForegroundColor Yellow
}

# 8. Provision Standard Taskbar Layout
Write-Host "[*] Konfiguriere standardisiertes Taskleisten-Layout..." -ForegroundColor Cyan
try {
    $taskbarXml = @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\File Explorer.lnk" />
        <taskbar:DesktopApp DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Firefox.lnk" />
        <taskbar:DesktopApp DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Word.lnk" />
        <taskbar:DesktopApp DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Excel.lnk" />
        <taskbar:DesktopApp DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\PowerPoint.lnk" />
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
    $defaultShell = "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell"
    if (-not (Test-Path $defaultShell)) { New-Item -ItemType Directory -Path $defaultShell -Force | Out-Null }
    [System.IO.File]::WriteAllText("$defaultShell\LayoutModification.xml", $taskbarXml, [System.Text.Encoding]::UTF8)

    $userDirs = Get-ChildItem "C:\Users" -Directory | Where-Object { $_.Name -notin @("All Users", "Default User", "Public") }
    foreach ($uDir in $userDirs) {
        $tbDir = Join-Path $uDir.FullName "AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
        if (-not (Test-Path $tbDir)) { New-Item -ItemType Directory -Path $tbDir -Force | Out-Null }

        Get-ChildItem -Path $tbDir -Filter "*Edge*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $tbDir -Filter "*Store*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $tbDir -Filter "*Outlook*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $tbDir -Filter "*Mail*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

        $explorerSrc = "$($uDir.FullName)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\File Explorer.lnk"
        if (-not (Test-Path $explorerSrc)) {
            $explorerSrc = "C:\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\File Explorer.lnk"
        }
        $copyMap = @(
            @{ Src = $explorerSrc; Dst = "$tbDir\File Explorer.lnk" },
            @{ Src = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Firefox.lnk"; Dst = "$tbDir\Firefox.lnk" },
            @{ Src = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Word.lnk"; Dst = "$tbDir\Word.lnk" },
            @{ Src = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Excel.lnk"; Dst = "$tbDir\Excel.lnk" },
            @{ Src = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\PowerPoint.lnk"; Dst = "$tbDir\PowerPoint.lnk" }
        )
        foreach ($map in $copyMap) {
            if (Test-Path $map.Src) {
                Copy-Item -Path $map.Src -Destination $map.Dst -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Write-Host "[+] Taskleisten-Layout konfiguriert (Explorer, Firefox, Office angeheftet; Edge, Store, Outlook entfernt)." -ForegroundColor Green
} catch {
    Write-Host "[-] Fehler beim Konfigurieren des Taskleisten-Layouts: $_" -ForegroundColor Yellow
}

# 9. Automated BIOS Hostname Assignment
Write-Host "[*] Prüfe Hardware-Seriennummer und Hostnamen-Zuordnung..." -ForegroundColor Cyan
try {
    $deviceMap = @{
        "PF1WVA11"               = "Caritas-T480-1"
        "PF0YG5PW"               = "Caritas-X1-1"
        "NXEG9EV00105209C977600" = "Caritas-Acer-1"
        "NXEG9EV00105209CB17600" = "Caritas-Acer-2"
        "NXEG9EV00105209CB47600" = "Caritas-Acer-3"
        "NXEG9EV00105209CBB7600" = "Caritas-Acer-4"
        "5CG6388SJG"             = "Caritas-HP-1"
        "5CG6502VZQ"             = "Caritas-HP-2"
    }

    $biosSerial = (Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber
    if ($biosSerial) { $biosSerial = $biosSerial.Trim() }

    if ($biosSerial -and $deviceMap.ContainsKey($biosSerial)) {
        $targetHost = $deviceMap[$biosSerial]
        if ($env:COMPUTERNAME -ine $targetHost) {
            Rename-Computer -NewName $targetHost -Force -ErrorAction SilentlyContinue
            Write-Host "[+] Computername basierend auf BIOS-Seriennummer ($biosSerial) auf '$targetHost' gesetzt (wird nach Neustart wirksam)." -ForegroundColor Green
        } else {
            Write-Host "[OK] Computername entspricht bereits der BIOS-Seriennummer ($targetHost)." -ForegroundColor Green
        }
    } else {
        Write-Host "[*] Seriennummer '$biosSerial' nicht in Zuweisungstabelle oder nicht lesbar. Computername ($env:COMPUTERNAME) unverändert." -ForegroundColor Gray
    }
} catch {
    Write-Host "[-] Fehler bei der BIOS-Hostnamen-Zuweisung: $_" -ForegroundColor Yellow
}

# 10. Microsoft Office 2024 LTSC Silent Activation
Write-Host "[*] Prüfe Microsoft Office 2024 LTSC Aktivierungsstatus..." -ForegroundColor Cyan
try {
    $officeKey = "9YQNX-W4TVK-74HXJ-YDFX6-QYM2Q"
    $osppCandidates = @(
        "$env:ProgramFiles\Microsoft Office\Office16\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office16\ospp.vbs"
    )
    $ospp = $osppCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($ospp) {
        $dstatus = & cscript.exe //Nologo "$ospp" /dstatus 2>&1 | Out-String
        if ($dstatus -match "---LICENSED---") {
            Write-Host "[OK] Microsoft Office ist bereits lizenziert und aktiviert." -ForegroundColor Green
        } else {
            Write-Host "[*] Installiere Volumenlizenzschlüssel für Office..." -ForegroundColor Yellow
            & cscript.exe //Nologo "$ospp" /inpkey:$officeKey 2>&1 | Out-Null
            Write-Host "[*] Aktiviere Office online..." -ForegroundColor Yellow
            & cscript.exe //Nologo "$ospp" /act 2>&1 | Out-Null
            $afterStatus = & cscript.exe //Nologo "$ospp" /dstatus 2>&1 | Out-String
            if ($afterStatus -match "---LICENSED---") {
                Write-Host "[+] Microsoft Office erfolgreich aktiviert (MAK-Schlüssel QYM2Q)." -ForegroundColor Green
            } else {
                Write-Host "[-] Office-Aktivierung konnte nicht unmittelbar bestätigt werden." -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "[*] Microsoft Office 16/2024 nicht installiert (ospp.vbs nicht vorhanden)." -ForegroundColor Gray
    }
} catch {
    Write-Host "[-] Fehler bei der Office-Aktivierung: $_" -ForegroundColor Yellow
}

# 11. TeamViewer Remote Administration Configuration
Write-Host "[*] Konfiguriere TeamViewer für unbeaufsichtigten Zugriff..." -ForegroundColor Cyan
try {
    $tvRegPaths = @(
        "HKLM:\SOFTWARE\TeamViewer",
        "HKLM:\SOFTWARE\WOW6432Node\TeamViewer"
    )
    foreach ($tvPath in $tvRegPaths) {
        if (-not (Test-Path $tvPath)) {
            New-Item -Path $tvPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        if (Test-Path $tvPath) {
            Set-ItemProperty -Path $tvPath -Name "Security_WinLogin" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $tvPath -Name "Always_Online" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $tvPath -Name "Autostart" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        }
    }

    $tvService = Get-Service -Name "TeamViewer" -ErrorAction SilentlyContinue
    if ($tvService) {
        Set-Service -Name "TeamViewer" -StartupType Automatic -ErrorAction SilentlyContinue
        if ($tvService.Status -ne "Running") {
            Start-Service -Name "TeamViewer" -ErrorAction SilentlyContinue
        }
        Write-Host "[+] TeamViewer-Dienst auf 'Automatisch' gesetzt und gestartet." -ForegroundColor Green
    }
    Write-Host "[+] TeamViewer-Richtlinien konfiguriert (Windows-Authentifizierung aktiv, Autostart aktiv)." -ForegroundColor Green
} catch {
    Write-Host "[-] Fehler bei der TeamViewer-Konfiguration: $_" -ForegroundColor Yellow
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
