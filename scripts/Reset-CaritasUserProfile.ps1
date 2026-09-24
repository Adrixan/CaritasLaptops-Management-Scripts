#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Automated user profile reset and clean slate enforcement script.
.DESCRIPTION
    Purges and resets a shared standard user profile (default: 'User') across any Windows 10/11 edition:
    1. Terminates active and disconnected logon sessions for the target user.
    2. Dismounts and deletes the user profile using the native Windows User Profile API (Win32_UserProfile).
    3. Cleans residual ProfileList registry references and orphaned backup keys (.bak).
    4. Guarantees that the local SAM user account exists as a standard unprivileged user without an expiration date.
    5. Enforces machine-wide policies blocking Microsoft Account linking, OneDrive file storage, and settings sync.
    6. Optionally provisions a Windows Scheduled Task (SYSTEM level) and a public desktop shortcut for one-click resets.
.PARAMETER TargetUsername
    The local standard username to reset. Default is 'User'.
.PARAMETER RegisterTask
    Registers an elevated Scheduled Task (running as NT AUTHORITY\SYSTEM) allowing unprivileged users or shortcuts to trigger a reset.
.PARAMETER CreateDesktopShortcut
    Creates an unprivileged desktop shortcut on C:\Users\Public\Desktop pointing to the scheduled task.
.PARAMETER InstallAll
    Convenience switch: registers the scheduled task with Builtin\Users execute rights and creates the public desktop shortcut.
.PARAMETER RebootAfterReset
    Initiates a clean operating system restart after profile deletion.
.PARAMETER DryRun
    Simulates the reset procedure and logs proposed actions without terminating sessions or deleting files.
.NOTES
    Compatible with all Windows 11 editions (Home, Pro, Enterprise, Education).
    Resets are strictly on-demand (patron desktop shortcut or administrator trigger).
    Logs operations to logs\UserReset.log.
#>
[CmdletBinding()]
param(
    [string]$TargetUsername = "User",
    [switch]$RegisterTask,
    [switch]$CreateDesktopShortcut,
    [switch]$InstallAll,
    [switch]$RebootAfterReset,
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

# Enforce UTF-8 console and pipeline encoding
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# 1. Logging Infrastructure (Dynamically Resolved)
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Item -Path ".").FullName }
$baseDir = Split-Path -Path $scriptDir -Parent
if (-not (Test-Path "$baseDir\scripts")) { $baseDir = $scriptDir }
$logDir = Join-Path $baseDir "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "UserReset.log"

function Write-ResetLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$timestamp] [$Level] $Message"
    Write-Host $logLine -ForegroundColor $Color
    try {
        Add-Content -Path $logFile -Value $logLine -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

Write-ResetLog "==========================================================" "START" ([ConsoleColor]::Cyan)
Write-ResetLog "Starte Bereinigung und Zurücksetzung des Benutzerkontos '$TargetUsername'" "START" ([ConsoleColor]::Cyan)
Write-ResetLog "Zielkonto: $TargetUsername | Computer: $env:COMPUTERNAME | Aufrufer: $env:USERNAME" "INFO" ([ConsoleColor]::Gray)

# 2. Enforce Isolation Policies (NoConnectedUser, DisableFileSyncNGSC, DisableSettingSync)
Write-ResetLog "[Schritt 1/6] Überprüfe System-Isolationsrichtlinien (MSA, OneDrive, Synchronisation)..." "INFO" ([ConsoleColor]::Yellow)

if (-not $DryRun) {
    Write-ResetLog "  -> Blockiere Microsoft-Konto Verknüpfung (NoConnectedUser=3)..." "ACTION" ([ConsoleColor]::Gray)
    $sysPolicy = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    if (-not (Test-Path $sysPolicy)) { New-Item -Path $sysPolicy -Force | Out-Null }
    New-ItemProperty -Path $sysPolicy -Name "NoConnectedUser" -Value 3 -PropertyType DWord -Force | Out-Null

    Write-ResetLog "  -> Deaktiviere OneDrive Dateisynchronisation..." "ACTION" ([ConsoleColor]::Gray)
    $odPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive"
    if (-not (Test-Path $odPolicy)) { New-Item -Path $odPolicy -Force | Out-Null }
    New-ItemProperty -Path $odPolicy -Name "DisableFileSyncNGSC" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $odPolicy -Name "DisableFileSync" -Value 1 -PropertyType DWord -Force | Out-Null

    Write-ResetLog "  -> Unterbinde Windows-Einstellungen-Synchronisation..." "ACTION" ([ConsoleColor]::Gray)
    $syncPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync"
    if (-not (Test-Path $syncPolicy)) { New-Item -Path $syncPolicy -Force | Out-Null }
    New-ItemProperty -Path $syncPolicy -Name "DisableSettingSync" -Value 2 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $syncPolicy -Name "DisableSettingSyncUserOverride" -Value 1 -PropertyType DWord -Force | Out-Null

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -ErrorAction SilentlyContinue
    Write-ResetLog "  [OK] Isolationsrichtlinien erfolgreich überprüft und aktiv." "INFO" ([ConsoleColor]::Green)
} else {
    Write-ResetLog "  [DryRun] Würde NoConnectedUser=3, DisableFileSyncNGSC=1, DisableSettingSync=2 erzwingen." "INFO" ([ConsoleColor]::Gray)
}

# 3. Terminate Active and Disconnected Sessions
Write-ResetLog "[Schritt 2/6] Prüfe und beende aktive Sitzungen für '$TargetUsername'..." "INFO" ([ConsoleColor]::Yellow)

if (-not $DryRun) {
    Write-ResetLog "  -> Überprüfe aktive Benutzersitzungen..." "ACTION" ([ConsoleColor]::Gray)
    $quserOutput = quser 2>$null
    if ($quserOutput) {
        foreach ($line in $quserOutput) {
            if ($line -match "(?i)\b$TargetUsername\b\s+(\S*)\s+(\d+)") {
                $sessId = $matches[2]
                Write-ResetLog "  -> Melde aktive Sitzung ID $sessId für '$TargetUsername' ab..." "ACTION" ([ConsoleColor]::Yellow)
                logoff $sessId 2>$null
            }
        }
    }

    Write-ResetLog "  -> Suche nach verbleibenden Hintergrundprozessen von '$TargetUsername'..." "ACTION" ([ConsoleColor]::Gray)
    $userProcesses = Get-Process -IncludeUserName -ErrorAction SilentlyContinue | Where-Object { $_.UserName -like "*\$TargetUsername" }
    if ($userProcesses) {
        Write-ResetLog "  -> Beende $($userProcesses.Count) Prozess(e) von '$TargetUsername'..." "ACTION" ([ConsoleColor]::Yellow)
        $userProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    } else {
        Write-ResetLog "  -> Keine verbleibenden Hintergrundprozesse gefunden." "ACTION" ([ConsoleColor]::Gray)
    }

    Write-ResetLog "  -> Warte auf Freigabe von Dateisperren durch den Benutzerprofildienst (ProfSvc)..." "ACTION" ([ConsoleColor]::Gray)
    Start-Sleep -Seconds 2
    Write-ResetLog "  [OK] Sitzungen und Prozesse bereinigt." "INFO" ([ConsoleColor]::Green)
} else {
    Write-ResetLog "  [DryRun] Würde Sitzungen und Prozesse von '$TargetUsername' beenden." "INFO" ([ConsoleColor]::Gray)
}

# 4. Delete Profile via Native CIM API (Win32_UserProfile)
Write-ResetLog "[Schritt 3/6] Lösche Benutzerprofil über die Windows-CIM-Schnittstelle..." "INFO" ([ConsoleColor]::Yellow)

Write-ResetLog "  -> Suche registriertes Profil in Win32_UserProfile..." "ACTION" ([ConsoleColor]::Gray)
$targetProfile = Get-CimInstance -ClassName Win32_UserProfile | Where-Object {
    $_.LocalPath -like "*\$TargetUsername" -and -not $_.Special
}

if ($targetProfile) {
    Write-ResetLog "  -> Registriertes Profil gefunden: $($targetProfile.LocalPath) (SID: $($targetProfile.SID))" "INFO" ([ConsoleColor]::Gray)
    if ($DryRun) {
        Write-ResetLog "  [DryRun] Würde Win32_UserProfile.Delete() für $($targetProfile.LocalPath) ausführen." "INFO" ([ConsoleColor]::Gray)
    } else {
        $maxAttempts = 3
        $purged = $false
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            try {
                Write-ResetLog "  -> Führe Profillöschung aus (Versuch $attempt von $maxAttempts)..." "ACTION" ([ConsoleColor]::Yellow)
                Remove-CimInstance -InputObject $targetProfile -ErrorAction Stop
                $purged = $true
                Write-ResetLog "  [OK] Benutzerprofil erfolgreich via Windows-CIM gelöscht." "ACTION" ([ConsoleColor]::Green)
                break
            } catch {
                Write-ResetLog "  -> Versuch $attempt ergab: $_. Wiederhole nach Freigabe..." "WARN" ([ConsoleColor]::DarkGray)
                Start-Sleep -Seconds 2
                $targetProfile = Get-CimInstance -ClassName Win32_UserProfile | Where-Object { $_.LocalPath -like "*\$TargetUsername" -and -not $_.Special }
                if (-not $targetProfile) {
                    $purged = $true
                    Write-ResetLog "  [OK] Profil nicht mehr vorhanden." "ACTION" ([ConsoleColor]::Green)
                    break
                }
            }
        }

        if (-not $purged) {
            Write-ResetLog "  -> Fallback: Versuche Löschung über WMI-Methode..." "WARN" ([ConsoleColor]::Yellow)
            $wmiProf = Get-WmiObject -Class Win32_UserProfile | Where-Object { $_.LocalPath -like "*\$TargetUsername" }
            if ($wmiProf) {
                try {
                    $wmiProf.Delete()
                    Write-ResetLog "  [OK] Profil via WMI-Fallback gelöscht." "ACTION" ([ConsoleColor]::Green)
                } catch {
                    Write-ResetLog "  [-] WMI-Löschung fehlgeschlagen: $_" "WARN" ([ConsoleColor]::Red)
                }
            }
        }
    }
} else {
    Write-ResetLog "  [OK] Kein registriertes Profil in Win32_UserProfile vorhanden (bereits sauber)." "INFO" ([ConsoleColor]::Green)
}

# 5. Clean Residual ProfileList Registry References & Filesystem Artifacts
Write-ResetLog "[Schritt 4/6] Bereinige Profilliste in der Registrierung und Dateisystem-Reste..." "INFO" ([ConsoleColor]::Yellow)

if (-not $DryRun) {
    Write-ResetLog "  -> Prüfe HKLM ProfileList auf verwaiste Einträge..." "ACTION" ([ConsoleColor]::Gray)
    $profileListKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
    $orphanedKeys = Get-ChildItem -Path $profileListKey -ErrorAction SilentlyContinue | Where-Object {
        $imgPath = (Get-ItemProperty $_.PSPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
        ($imgPath -like "*\$TargetUsername") -or ($_.PSChildName -like "*$TargetUsername*.bak")
    }

    foreach ($key in $orphanedKeys) {
        Write-ResetLog "  -> Entferne verwaisten Registrierungsschlüssel: $($key.PSChildName)" "ACTION" ([ConsoleColor]::Yellow)
        Remove-Item -Path $key.PSPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    $folderPath = "C:\Users\$TargetUsername"
    if (Test-Path $folderPath) {
        Write-ResetLog "  -> Entferne verbleibenden Profilordner: $folderPath..." "ACTION" ([ConsoleColor]::Yellow)
        Remove-Item -Path $folderPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-ResetLog "  [OK] Registrierung und Profilordner bereinigt." "INFO" ([ConsoleColor]::Green)
} else {
    Write-ResetLog "  [DryRun] Würde ProfileList-Schlüssel bereinigen und C:\Users\$TargetUsername entfernen." "INFO" ([ConsoleColor]::Gray)
}

# 6. Ensure Local User Account Exists & Enforce Standard Privileges & Auto-Logon
Write-ResetLog "[Schritt 5/6] Konfiguriere Benutzerkonto '$TargetUsername' & automatische Anmeldung..." "INFO" ([ConsoleColor]::Yellow)

if (-not $DryRun) {
    Write-ResetLog "  -> Überprüfe lokales Benutzerkonto '$TargetUsername'..." "ACTION" ([ConsoleColor]::Gray)
    $usersGroupName = (Get-LocalGroup | Where-Object { $_.SID.Value -eq "S-1-5-32-545" }).Name
    $adminGroupName = (Get-LocalGroup | Where-Object { $_.SID.Value -eq "S-1-5-32-544" }).Name

    $localUser = Get-LocalUser -Name $TargetUsername -ErrorAction SilentlyContinue
    if (-not $localUser) {
        Write-ResetLog "  -> Erstelle lokales Benutzerkonto '$TargetUsername'..." "ACTION" ([ConsoleColor]::Green)
        New-LocalUser -Name $TargetUsername -Description "Default shared standard user" -NoPassword | Out-Null
    }

    Set-LocalUser -Name $TargetUsername -PasswordNeverExpires $true | Out-Null
    Add-LocalGroupMember -Group $usersGroupName -Member $TargetUsername -ErrorAction SilentlyContinue

    # Ensure target is not an administrator
    $isAdmin = Get-LocalGroupMember -Group $adminGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*\$TargetUsername" }
    if ($isAdmin) {
        Remove-LocalGroupMember -Group $adminGroupName -Member $TargetUsername
        Write-ResetLog "  -> Entferne Administrator-Berechtigungen von '$TargetUsername'..." "WARN" ([ConsoleColor]::Yellow)
    }

    # Configure Autologon for TargetUsername
    Write-ResetLog "  -> Richte automatische Windows-Anmeldung (Autologon) für '$TargetUsername' ein..." "ACTION" ([ConsoleColor]::Gray)
    $winlogonKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $winlogonKey -Name "AutoAdminLogon" -Value "1" -Type String -Force
    Set-ItemProperty -Path $winlogonKey -Name "DefaultUserName" -Value $TargetUsername -Type String -Force
    Set-ItemProperty -Path $winlogonKey -Name "DefaultDomainName" -Value $env:COMPUTERNAME -Type String -Force
    Set-ItemProperty -Path $winlogonKey -Name "DefaultPassword" -Value "" -Type String -Force
    Set-ItemProperty -Path $winlogonKey -Name "ForceAutoLogon" -Value "1" -Type String -Force
    Set-ItemProperty -Path $winlogonKey -Name "LastUsedUsername" -Value $TargetUsername -Type String -Force
    Remove-ItemProperty -Path $winlogonKey -Name "AutoLogonCount" -ErrorAction SilentlyContinue

    Write-ResetLog "  [OK] Benutzerkonto und automatische Anmeldung erfolgreich konfiguriert." "INFO" ([ConsoleColor]::Green)
} else {
    Write-ResetLog "  [DryRun] Würde Benutzerkonto '$TargetUsername' und Autologon konfigurieren." "INFO" ([ConsoleColor]::Gray)
}

# 7. Provisioning Facilities (Scheduled Task, Desktop Shortcut, Legacy Cleanup)
Write-ResetLog "[Schritt 6/6] Überprüfe Bereitstellung (Aufgabenplanung & Desktop-Verknüpfung)..." "INFO" ([ConsoleColor]::Yellow)
$scriptPath = if ($PSCommandPath) { $PSCommandPath } else { Join-Path $scriptDir "Reset-CaritasUserProfile.ps1" }

if ($RegisterTask -or $InstallAll) {
    Write-ResetLog "  -> Konfiguriere erhöhte geplante Aufgabe 'Caritas-ResetUserSession'..." "INFO" ([ConsoleColor]::Yellow)
    if (-not $DryRun) {
        $taskName = "Caritas-ResetUserSession"
        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -TargetUsername `"$TargetUsername`""
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
        Write-ResetLog "  [OK] Geplante Aufgabe '$taskName' erfolgreich unter SYSTEM registriert." "ACTION" ([ConsoleColor]::Green)

        # Grant Builtin\Users execute rights so standard patrons can trigger the reset via shortcut
        try {
            $scheduler = New-Object -ComObject "Schedule.Service"
            $scheduler.Connect()
            $folder = $scheduler.GetFolder("\")
            $taskObj = $folder.GetTask($taskName)
            $currentSddl = $taskObj.GetSecurityDescriptor(4)
            if ($currentSddl -notmatch ";;;BU\)" -and $currentSddl -notmatch "0x12019f;;;BU") {
                $taskObj.SetSecurityDescriptor($currentSddl + "(A;;0x12019f;;;BU)", 0)
                Write-ResetLog "  [OK] Ausführungsberechtigungen für Builtin\Users vergeben." "ACTION" ([ConsoleColor]::Green)
            }
        } catch {
            Write-ResetLog "  Notice: Task COM security descriptor update: $_" "WARN" ([ConsoleColor]::DarkGray)
        }

        $taskFilePath = "$env:SystemRoot\System32\Tasks\$taskName"
        if (Test-Path $taskFilePath) {
            & icacls.exe $taskFilePath /grant "*S-1-5-32-545:(RX)" /Q | Out-Null
        }
    } else {
        Write-ResetLog "  [DryRun] Würde geplante Aufgabe 'Caritas-ResetUserSession' registrieren." "INFO" ([ConsoleColor]::Gray)
    }
}

if ($CreateDesktopShortcut -or $InstallAll) {
    $shortcutFileName = "Sitzung zur$([char]0x00FC)cksetzen.lnk"
    Write-ResetLog "  -> Erstelle öffentliche Desktop-Verknüpfung '$shortcutFileName'..." "INFO" ([ConsoleColor]::Yellow)
    if (-not $DryRun) {
        $publicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
        # Remove any previously misencoded shortcuts
        Get-ChildItem -Path $publicDesktop -Filter "*cksetzen.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

        $shortcutPath = Join-Path $publicDesktop $shortcutFileName
        $wshShell = New-Object -ComObject WScript.Shell
        $shortcut = $wshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "C:\Windows\System32\schtasks.exe"
        $shortcut.Arguments = "/run /tn `"Caritas-ResetUserSession`""
        $shortcut.IconLocation = "C:\Windows\System32\shell32.dll,238"
        $shortcut.Description = "Setzt das Benutzerkonto '$TargetUsername' auf den sauberen Ausgangszustand zur$([char]0x00FC)ck."
        $shortcut.WorkingDirectory = "C:\Windows\System32"
        $shortcut.Save()
        Write-ResetLog "  [OK] Desktop-Verknüpfung unter '$shortcutPath' bereitgestellt." "ACTION" ([ConsoleColor]::Green)
    } else {
        Write-ResetLog "  [DryRun] Würde Desktop-Verknüpfung '$shortcutFileName' erstellen." "INFO" ([ConsoleColor]::Gray)
    }
} else {
    Write-ResetLog "  -> Bereitstellung bereits abgeschlossen." "ACTION" ([ConsoleColor]::Gray)
}

# 8. Decommission Legacy Boot-Time Wipe Task (Enforce On-Demand Reset Only)
if (-not $DryRun) {
    $legacyBootTask = Get-ScheduledTask -TaskName "Caritas-ResetUserOnBoot" -ErrorAction SilentlyContinue
    if ($legacyBootTask) {
        Write-ResetLog "  -> Entferne alte Boot-Reset-Aufgabe 'Caritas-ResetUserOnBoot'..." "ACTION" ([ConsoleColor]::Yellow)
        Unregister-ScheduledTask -TaskName "Caritas-ResetUserOnBoot" -Confirm:$false -ErrorAction SilentlyContinue
        Write-ResetLog "  [OK] Alte Boot-Aufgabe deinstalliert." "ACTION" ([ConsoleColor]::Green)
    }
}

Write-ResetLog "==========================================================" "DONE" ([ConsoleColor]::Cyan)
Write-ResetLog "Bereinigung und Zurücksetzung erfolgreich abgeschlossen." "DONE" ([ConsoleColor]::Cyan)
Write-ResetLog "Protokolldatei: $logFile" "DONE" ([ConsoleColor]::White)

if ($RebootAfterReset -and -not $DryRun) {
    Write-ResetLog "Initiating system reboot in 5 seconds..." "ACTION" ([ConsoleColor]::Yellow)
    shutdown /r /t 5 /c "Caritas User profile reset complete. Rebooting."
}
