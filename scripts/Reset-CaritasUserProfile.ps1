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
.PARAMETER RegisterBootTask
    Registers a scheduled task to automatically purge and reset the target profile on every system startup.
.PARAMETER InstallAll
    Convenience switch: registers the scheduled task, desktop shortcut, and boot-time clean slate task.
.PARAMETER RebootAfterReset
    Initiates a clean operating system restart after profile deletion.
.PARAMETER DryRun
    Simulates the reset procedure and logs proposed actions without terminating sessions or deleting files.
.NOTES
    Compatible with all Windows 11 editions (Home, Pro, Enterprise, Education).
    Logs operations to C:\Caritas\Logs\UserReset.log.
#>
[CmdletBinding()]
param(
    [string]$TargetUsername = "User",
    [switch]$RegisterTask,
    [switch]$CreateDesktopShortcut,
    [switch]$RegisterBootTask,
    [switch]$InstallAll,
    [switch]$RebootAfterReset,
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

# 1. Logging Infrastructure
$logDir = "C:\Caritas\Logs"
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
        Add-Content -Path $logFile -Value $logLine -ErrorAction SilentlyContinue
    } catch {}
}

Write-ResetLog "==========================================================" "START" ([ConsoleColor]::Cyan)
Write-ResetLog "Starting User Profile Reset and Clean Slate Automation" "START" ([ConsoleColor]::Cyan)
Write-ResetLog "Target Account: $TargetUsername | Host: $env:COMPUTERNAME | Caller: $env:USERNAME" "INFO" ([ConsoleColor]::Gray)

# 2. Enforce Isolation Policies (NoConnectedUser, DisableFileSyncNGSC, DisableSettingSync)
Write-ResetLog "[Step 1/5] Verifying Machine Isolation Policies (MSA, OneDrive, Settings Sync)..." "INFO" ([ConsoleColor]::Yellow)

if (-not $DryRun) {
    # Block Microsoft Account linking
    $sysPolicy = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    if (-not (Test-Path $sysPolicy)) { New-Item -Path $sysPolicy -Force | Out-Null }
    Set-ItemProperty -Path $sysPolicy -Name "NoConnectedUser" -Value 3 -Type DWord -Force | Out-Null

    # Block OneDrive sync and file storage
    $odPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive"
    if (-not (Test-Path $odPolicy)) { New-Item -Path $odPolicy -Force | Out-Null }
    Set-ItemProperty -Path $odPolicy -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force | Out-Null
    Set-ItemProperty -Path $odPolicy -Name "DisableFileSync" -Value 1 -Type DWord -Force | Out-Null

    # Block Settings Sync
    $syncPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync"
    if (-not (Test-Path $syncPolicy)) { New-Item -Path $syncPolicy -Force | Out-Null }
    Set-ItemProperty -Path $syncPolicy -Name "DisableSettingSync" -Value 2 -Type DWord -Force | Out-Null
    Set-ItemProperty -Path $syncPolicy -Name "DisableSettingSyncUserOverride" -Value 1 -Type DWord -Force | Out-Null

    # Suppress OneDrive per-user installer
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -ErrorAction SilentlyContinue

    Write-ResetLog "  [OK] Isolation policies active: MSA blocked (3), OneDrive blocked (1), SettingSync blocked (2)." "INFO" ([ConsoleColor]::Green)
} else {
    Write-ResetLog "  [DryRun] Would enforce NoConnectedUser=3, DisableFileSyncNGSC=1, DisableSettingSync=2." "INFO" ([ConsoleColor]::Gray)
}

# 3. Terminate Active and Disconnected Sessions
Write-ResetLog "[Step 2/5] Checking for active or disconnected sessions for '$TargetUsername'..." "INFO" ([ConsoleColor]::Yellow)

if (-not $DryRun) {
    $quserOutput = quser 2>$null
    if ($quserOutput) {
        foreach ($line in $quserOutput) {
            if ($line -match "(?i)\b$TargetUsername\b\s+(\S*)\s+(\d+)") {
                $sessId = $matches[2]
                Write-ResetLog "  Terminating session ID $sessId for '$TargetUsername'..." "ACTION" ([ConsoleColor]::Yellow)
                logoff $sessId 2>$null
            }
        }
    }

    # Stop any background tasks remaining under TargetUsername
    $userProcesses = Get-Process -IncludeUserName -ErrorAction SilentlyContinue | Where-Object { $_.UserName -like "*\$TargetUsername" }
    if ($userProcesses) {
        Write-ResetLog "  Stopping $($userProcesses.Count) remaining background process(es) for '$TargetUsername'..." "ACTION" ([ConsoleColor]::Yellow)
        $userProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    # Wait for User Profile Service (ProfSvc) to flush and dismount NTUSER.DAT
    Start-Sleep -Seconds 3
} else {
    Write-ResetLog "  [DryRun] Would log off session and terminate background processes for '$TargetUsername'." "INFO" ([ConsoleColor]::Gray)
}

# 4. Delete Profile via Native CIM API (Win32_UserProfile)
Write-ResetLog "[Step 3/5] Locating and purging user profile via Win32_UserProfile..." "INFO" ([ConsoleColor]::Yellow)

$targetProfile = Get-CimInstance -ClassName Win32_UserProfile | Where-Object {
    $_.LocalPath -like "*\$TargetUsername" -and -not $_.Special
}

if ($targetProfile) {
    Write-ResetLog "  Found registered profile: $($targetProfile.LocalPath) (SID: $($targetProfile.SID), Loaded: $($targetProfile.Loaded))" "INFO" ([ConsoleColor]::Gray)
    if ($DryRun) {
        Write-ResetLog "  [DryRun] Would call Win32_UserProfile.Delete() for profile at $($targetProfile.LocalPath)." "INFO" ([ConsoleColor]::Gray)
    } else {
        # Retry loop to allow ProfSvc handle release
        $maxAttempts = 3
        $purged = $false
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            try {
                Write-ResetLog "  Executing profile deletion (Attempt $attempt of $maxAttempts)..." "ACTION" ([ConsoleColor]::Yellow)
                Remove-CimInstance -InputObject $targetProfile -ErrorAction Stop
                $purged = $true
                Write-ResetLog "  [SUCCESS] Profile deleted successfully via CIM." "ACTION" ([ConsoleColor]::Green)
                break
            } catch {
                Write-ResetLog "  Notice: CIM deletion attempt $attempt returned: $_" "WARN" ([ConsoleColor]::DarkGray)
                Start-Sleep -Seconds 2
                # Re-fetch instance in case state changed
                $targetProfile = Get-CimInstance -ClassName Win32_UserProfile | Where-Object { $_.LocalPath -like "*\$TargetUsername" -and -not $_.Special }
                if (-not $targetProfile) {
                    $purged = $true
                    break
                }
            }
        }

        if (-not $purged) {
            Write-ResetLog "  Fallback: Attempting WMI Delete method..." "WARN" ([ConsoleColor]::Yellow)
            $wmiProf = Get-WmiObject -Class Win32_UserProfile | Where-Object { $_.LocalPath -like "*\$TargetUsername" }
            if ($wmiProf) {
                try {
                    $wmiProf.Delete()
                    Write-ResetLog "  [SUCCESS] Profile deleted via WMI fallback." "ACTION" ([ConsoleColor]::Green)
                } catch {
                    Write-ResetLog "  WMI Delete failed: $_" "WARN" ([ConsoleColor]::Red)
                }
            }
        }
    }
} else {
    Write-ResetLog "  [OK] No registered profile directory found for '$TargetUsername'." "INFO" ([ConsoleColor]::Green)
}

# 5. Clean Residual ProfileList Registry References & Filesystem Artifacts
Write-ResetLog "[Step 4/5] Scrubbing residual ProfileList registry keys and directory locks..." "INFO" ([ConsoleColor]::Yellow)

if (-not $DryRun) {
    $profileListKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
    $orphanedKeys = Get-ChildItem -Path $profileListKey -ErrorAction SilentlyContinue | Where-Object {
        $imgPath = (Get-ItemProperty $_.PSPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
        ($imgPath -like "*\$TargetUsername") -or ($_.PSChildName -like "*$TargetUsername*.bak")
    }

    foreach ($key in $orphanedKeys) {
        Write-ResetLog "  Removing residual ProfileList key: $($key.PSChildName)" "ACTION" ([ConsoleColor]::Yellow)
        Remove-Item -Path $key.PSPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    $folderPath = "C:\Users\$TargetUsername"
    if (Test-Path $folderPath) {
        Write-ResetLog "  Purging remaining directory contents at $folderPath..." "ACTION" ([ConsoleColor]::Yellow)
        Remove-Item -Path $folderPath -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-ResetLog "  [DryRun] Would scrub residual ProfileList keys and remove C:\Users\$TargetUsername." "INFO" ([ConsoleColor]::Gray)
}

# 6. Ensure Local User Account Exists & Enforce Standard Privileges
Write-ResetLog "[Step 5/5] Ensuring local user '$TargetUsername' exists in SAM as an unprivileged user..." "INFO" ([ConsoleColor]::Yellow)

if (-not $DryRun) {
    $usersGroupName = (Get-LocalGroup | Where-Object { $_.SID.Value -eq "S-1-5-32-545" }).Name
    $adminGroupName = (Get-LocalGroup | Where-Object { $_.SID.Value -eq "S-1-5-32-544" }).Name

    $localUser = Get-LocalUser -Name $TargetUsername -ErrorAction SilentlyContinue
    if (-not $localUser) {
        Write-ResetLog "  Creating local user '$TargetUsername'..." "ACTION" ([ConsoleColor]::Green)
        New-LocalUser -Name $TargetUsername -Description "Default shared standard user" -NoPassword | Out-Null
    }

    Set-LocalUser -Name $TargetUsername -PasswordNeverExpires $true | Out-Null
    Add-LocalGroupMember -Group $usersGroupName -Member $TargetUsername -ErrorAction SilentlyContinue

    # Ensure target is not an administrator
    $isAdmin = Get-LocalGroupMember -Group $adminGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*\$TargetUsername" }
    if ($isAdmin) {
        Remove-LocalGroupMember -Group $adminGroupName -Member $TargetUsername
        Write-ResetLog "  [ACTION] Removed administrative privileges from '$TargetUsername'." "WARN" ([ConsoleColor]::Yellow)
    }

    Write-ResetLog "  [OK] Local user '$TargetUsername' verified (Standard User, Password Never Expires)." "INFO" ([ConsoleColor]::Green)
} else {
    Write-ResetLog "  [DryRun] Would verify local user '$TargetUsername' and enforce membership in Users group." "INFO" ([ConsoleColor]::Gray)
}

# 7. Provisioning Facilities (Scheduled Task, Desktop Shortcut, Boot Task)
$scriptPath = "C:\Caritas\Scripts\Reset-CaritasUserProfile.ps1"

if ($RegisterTask -or $InstallAll) {
    Write-ResetLog "Configuring Elevated Scheduled Task 'Caritas-ResetUserSession'..." "INFO" ([ConsoleColor]::Yellow)
    if (-not $DryRun) {
        $taskName = "Caritas-ResetUserSession"
        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -TargetUsername `"$TargetUsername`""
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
        Write-ResetLog "  [SUCCESS] Scheduled Task '$taskName' registered under NT AUTHORITY\SYSTEM." "ACTION" ([ConsoleColor]::Green)
    } else {
        Write-ResetLog "  [DryRun] Would register Scheduled Task 'Caritas-ResetUserSession'." "INFO" ([ConsoleColor]::Gray)
    }
}

if ($CreateDesktopShortcut -or $InstallAll) {
    $shortcutFileName = "Sitzung zur$([char]0x00FC)cksetzen.lnk"
    Write-ResetLog "Creating Public Desktop Shortcut '$shortcutFileName'..." "INFO" ([ConsoleColor]::Yellow)
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
        Write-ResetLog "  [SUCCESS] Shortcut deployed to '$shortcutPath'." "ACTION" ([ConsoleColor]::Green)
    } else {
        Write-ResetLog "  [DryRun] Would create desktop shortcut '$shortcutFileName'." "INFO" ([ConsoleColor]::Gray)
    }
}

if ($RegisterBootTask -or $InstallAll) {
    Write-ResetLog "Configuring Boot-Time Scheduled Task 'Caritas-ResetUserOnBoot'..." "INFO" ([ConsoleColor]::Yellow)
    if (-not $DryRun) {
        $bootTaskName = "Caritas-ResetUserOnBoot"
        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -TargetUsername `"$TargetUsername`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $bootTaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        Write-ResetLog "  [SUCCESS] Boot Task '$bootTaskName' registered for system startup." "ACTION" ([ConsoleColor]::Green)
    } else {
        Write-ResetLog "  [DryRun] Would register Boot Task 'Caritas-ResetUserOnBoot'." "INFO" ([ConsoleColor]::Gray)
    }
}

Write-ResetLog "==========================================================" "DONE" ([ConsoleColor]::Cyan)
Write-ResetLog "User profile reset operations finished successfully." "DONE" ([ConsoleColor]::Cyan)
Write-ResetLog "Audit log: $logFile" "DONE" ([ConsoleColor]::White)

if ($RebootAfterReset -and -not $DryRun) {
    Write-ResetLog "Initiating system reboot in 5 seconds..." "ACTION" ([ConsoleColor]::Yellow)
    shutdown /r /t 5 /c "Caritas User profile reset complete. Rebooting."
}
