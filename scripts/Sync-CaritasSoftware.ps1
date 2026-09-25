#Requires -RunAsAdministrator
<#
.SYNOPSIS
    General computer software and driver synchronization script.
.DESCRIPTION
    1. Locates, verifies, and updates the Windows Package Manager (winget) dynamically across any user profile.
    2. Enforces retention policy by dynamically detecting and removing disallowed software via registry heuristics and winget (no hardcoded GUIDs or machine-specific paths).
    3. Verifies that all required baseline applications are installed (installing any missing ones via winget).
    4. Upgrades all kept applications to the most recent version via winget and Office Click-to-Run.
    5. Queries Windows Update online for all pending software, hardware driver, firmware, and optional updates dynamically for any manufacturer (Lenovo, HP, Dell, Asus, Acer, Surface, etc.), downloads them, and silently installs them.
.NOTES
    Works on any standard Windows 10/11 laptop or desktop computer.
    Logs operations with timestamps to logs\SoftwareSync.log.
#>
[CmdletBinding()]
param(
    [switch]$SkipUpgrade,
    [switch]$SkipWindowsUpdate,
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

# Enforce UTF-8 console and pipeline encoding
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# 1. Setup Logging Infrastructure (Dynamically Resolved)
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Item -Path ".").FullName }
$baseDir = Split-Path -Path $scriptDir -Parent
if (-not (Test-Path "$baseDir\scripts")) { $baseDir = $scriptDir }
$logDir = Join-Path $baseDir "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "SoftwareSync.log"

function Write-SyncLog {
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

Write-SyncLog "==========================================================" "START" ([ConsoleColor]::Cyan)
Write-SyncLog "Starting Software and Driver Synchronization" "START" ([ConsoleColor]::Cyan)
Write-SyncLog "Host: $env:COMPUTERNAME | Current User: $env:USERNAME" "INFO" ([ConsoleColor]::Gray)

# 2. Phase 1: Dynamically Locate and Verify Windows Package Manager (winget)
Write-SyncLog "[Phase 1/5] Dynamically resolving Windows Package Manager (winget)..." "INFO" ([ConsoleColor]::Yellow)

$wingetExe = $null

# A. Check system PATH
$cmd = Get-Command "winget" -ErrorAction SilentlyContinue
if ($cmd) {
    $wingetExe = $cmd.Source
}

# B. Check current user's LOCALAPPDATA
if (-not $wingetExe -or -not (Test-Path $wingetExe)) {
    if ($env:LOCALAPPDATA -and (Test-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe")) {
        $wingetExe = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
    }
}

# C. Dynamically check all user profiles on this computer (no hardcoded usernames)
if (-not $wingetExe -or -not (Test-Path $wingetExe)) {
    $anyUserWinget = Get-ChildItem -Path "C:\Users\*\AppData\Local\Microsoft\WindowsApps\winget.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($anyUserWinget) {
        $wingetExe = $anyUserWinget.FullName
    }
}

# D. Dynamically check WindowsApps system directory
if (-not $wingetExe -or -not (Test-Path $wingetExe)) {
    $found = Get-ChildItem -Path "C:\Program Files\WindowsApps" -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        $wingetExe = $found.FullName
    }
}

# E. If not present on system, attempt package registration
if (-not $wingetExe) {
    Write-SyncLog "Windows Package Manager not found in standard paths. Attempting package registration..." "WARN" ([ConsoleColor]::Yellow)
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
        if ($env:LOCALAPPDATA -and (Test-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe")) {
            $wingetExe = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
        }
    } catch {
        Write-SyncLog "Notice: Could not register DesktopAppInstaller: $_" "WARN" ([ConsoleColor]::DarkGray)
    }
}

if ($wingetExe -and (Test-Path $wingetExe)) {
    try {
        $ver = & $wingetExe --version 2>$null
        Write-SyncLog "Using Windows Package Manager version: $ver ($wingetExe)" "SUCCESS" ([ConsoleColor]::Green)
        Write-SyncLog "Updating package manager source catalogs..." "INFO" ([ConsoleColor]::Gray)
        & $wingetExe source update --accept-source-agreements 2>$null | Out-Null
    } catch {
        Write-SyncLog "Notice: winget source update returned: $_" "WARN" ([ConsoleColor]::DarkGray)
    }
} else {
    Write-SyncLog "Warning: winget executable could not be verified; will rely on native uninstallers." "WARN" ([ConsoleColor]::Yellow)
}

# 3. Phase 2: Enforce Removal of Disallowed Applications (Dynamic Discovery)
Write-SyncLog "[Phase 2/5] Enforcing software retention policy: removing disallowed software..." "INFO" ([ConsoleColor]::Yellow)

function Invoke-UniversalUninstall {
    param(
        [string]$NamePattern,
        [string]$WingetId,
        [switch]$DryRunMode
    )

    Write-SyncLog "Checking removal status for '$NamePattern'..." "INFO" ([ConsoleColor]::White)

    $regHives = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    # Dynamically search user hives in HKEY_USERS for per-user installations
    Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | ForEach-Object {
        $sid = $_.PSChildName
        if ($sid -notmatch "_Classes$" -and $sid -match "^S-1-5-21-") {
            $regHives += "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
        }
    }

    $foundEntries = @()
    foreach ($path in $regHives) {
        $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -and ($_.DisplayName -like $NamePattern) -and -not $_.SystemComponent
        }
        if ($items) {
            $foundEntries += $items
        }
    }

    if ($foundEntries.Count -eq 0) {
        # Check via winget
        if ($wingetExe -and $WingetId) {
            $wgFound = & $wingetExe list --id $WingetId --exact --accept-source-agreements 2>$null
            if ($LASTEXITCODE -eq 0 -and $wgFound -match [regex]::Escape($WingetId)) {
                Write-SyncLog "  Found '$NamePattern' via winget ($WingetId). Uninstalling..." "ACTION" ([ConsoleColor]::Magenta)
                if (-not $DryRunMode) {
                    & $wingetExe uninstall --id $WingetId --silent --accept-source-agreements 2>$null | Out-Null
                }
            }
        }
        return
    }

    foreach ($entry in $foundEntries) {
        $displayName = $entry.DisplayName
        $uninstallStr = $entry.UninstallString
        $quietUninstallStr = $entry.QuietUninstallString

        Write-SyncLog "  Detected installed package: '$displayName'" "INFO" ([ConsoleColor]::Yellow)

        if ($DryRunMode) {
            Write-SyncLog "  [DryRun] Would uninstall '$displayName'." "INFO" ([ConsoleColor]::Gray)
            continue
        }

        # 1. QuietUninstallString if available
        if ($quietUninstallStr) {
            Write-SyncLog "  Executing quiet uninstaller..." "ACTION" ([ConsoleColor]::Magenta)
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$quietUninstallStr`"" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        }
        # 2. MSI uninstaller
        elseif ($uninstallStr -match "(?i)msiexec(\.exe)?\s+/[ix]\s*(\{[0-9a-fA-F-]+\})") {
            $guid = $matches[2]
            Write-SyncLog "  Executing silent MSI uninstall for GUID $guid..." "ACTION" ([ConsoleColor]::Magenta)
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/x", $guid, "/qn", "/norestart" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        }
        # 3. Standard executable uninstaller
        elseif ($uninstallStr) {
            $exePath = $uninstallStr.Trim()
            $exeArgs = ""
            if ($exePath -match '^"([^"]+)"\s*(.*)$') {
                $exePath = $matches[1]
                $exeArgs = $matches[2]
            } elseif ($exePath -match '^([^\s]+)\s*(.*)$') {
                $exePath = $matches[1]
                $exeArgs = $matches[2]
            }

            if (Test-Path $exePath) {
                $silentFlag = if ($exePath -like "*unins*") { "/SILENT /VERYSILENT /NORESTART" } else { "/S" }
                $finalArgs = if ($exeArgs) { "$exeArgs $silentFlag" } else { $silentFlag }
                Write-SyncLog "  Executing silent uninstaller: $exePath $finalArgs" "ACTION" ([ConsoleColor]::Magenta)
                Start-Process -FilePath $exePath -ArgumentList $finalArgs -Wait -NoNewWindow -ErrorAction SilentlyContinue
            }
        }

        # Fallback to winget
        if ($wingetExe -and $WingetId) {
            & $wingetExe uninstall --id $WingetId --silent --accept-source-agreements 2>$null | Out-Null
        }
    }
}

# Disallowed software defined by policy (dynamically discovered on any machine)
$disallowedWin32Patterns = @(
    @{ Pattern = "*Blender*"; WingetId = "BlenderFoundation.Blender" },
    @{ Pattern = "*Discord*"; WingetId = "XPDC2RH70K22MN" },
    @{ Pattern = "*Discord*"; WingetId = "Discord.Discord" },
    @{ Pattern = "*FileZilla*"; WingetId = "TimKosse.FileZilla.Client" },
    @{ Pattern = "*Git*"; WingetId = "Git.Git" },
    @{ Pattern = "*Google Earth*"; WingetId = "Google.GoogleEarthPro" },
    @{ Pattern = "*Notepad++*"; WingetId = "Notepad++.Notepad++" },
    @{ Pattern = "*PuTTY*"; WingetId = "PuTTY.PuTTY" },
    @{ Pattern = "*Python*"; WingetId = "Python.Python.3.13" },
    @{ Pattern = "*WinMerge*"; WingetId = "ThingamahoochieSoftware.WinMerge" },
    @{ Pattern = "*WinSCP*"; WingetId = "WinSCP.WinSCP" },
    @{ Pattern = "*Zoom*"; WingetId = "Zoom.Zoom" }
)

foreach ($target in $disallowedWin32Patterns) {
    Invoke-UniversalUninstall -NamePattern $target.Pattern -WingetId $target.WingetId -DryRunMode:$DryRun
}

# Dedicated purge for Discord and Discord System Helper (machine-wide Squirrel, Run keys, shortcuts)
Write-SyncLog "Checking for residual Discord and Discord System Helper artifacts..." "INFO" ([ConsoleColor]::Yellow)
if (-not $DryRun) {
    Get-Process -Name "*discord*", "*DiscordSystemHelper*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" -Name "Discord" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "Discord" -ErrorAction SilentlyContinue
    if (Test-Path "C:\ProgramData\SquirrelMachineInstalls\Discord.exe") {
        Remove-Item -Path "C:\ProgramData\SquirrelMachineInstalls\Discord.exe" -Force -ErrorAction SilentlyContinue
    }
    if ((Test-Path "C:\ProgramData\SquirrelMachineInstalls") -and ((Get-ChildItem "C:\ProgramData\SquirrelMachineInstalls" -ErrorAction SilentlyContinue).Count -eq 0)) {
        Remove-Item -Path "C:\ProgramData\SquirrelMachineInstalls" -Force -Recurse -ErrorAction SilentlyContinue
    }
    Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | ForEach-Object {
        $sid = $_.PSChildName
        $rKey = "Registry::HKEY_USERS\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        if (Test-Path $rKey) {
            Remove-ItemProperty -Path $rKey -Name "Discord" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $rKey -Name "DiscordSystemHelper" -ErrorAction SilentlyContinue
        }
        $uKey = "Registry::HKEY_USERS\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Discord"
        if (Test-Path $uKey) {
            Remove-Item -Path $uKey -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Get-ChildItem -Path "C:\Users\*\AppData\Local\Discord*" -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "C:\Users\*\AppData\Roaming\*discord*" -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "C:\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\*discord*" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\*discord*" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "C:\Users\*\Desktop\*discord*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "C:\Users\Public\Desktop\*discord*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

# Clean any residual user-level Python package caches dynamically across all user profiles
Get-ChildItem -Path "C:\Users\*\AppData\Local\Package Cache" -Filter "python-*.exe" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    Write-SyncLog "Cleaning residual Python installer at $($_.FullName)..." "ACTION" ([ConsoleColor]::Magenta)
    if (-not $DryRun) {
        Start-Process -FilePath $_.FullName -ArgumentList "/uninstall", "/quiet", "/norestart" -Wait -NoNewWindow -ErrorAction SilentlyContinue
    }
}

# Disallowed AppX / Modern Windows Packages
$disallowedAppx = @(
    "Clipchamp.Clipchamp",
    "Microsoft.BingNews",
    "Microsoft.BingSearch",
    "Microsoft.BingWeather",
    "Microsoft.Edge.GameAssist",
    "Microsoft.GamingApp",
    "Microsoft.GetHelp",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.Todos",
    "Microsoft.WindowsAlarms",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.YourPhone",
    "Microsoft.ZuneMusic",
    "MicrosoftCorporationII.QuickAssist",
    "NotepadPlusPlus",
    "WinMerge"
)

foreach ($pkg in $disallowedAppx) {
    # 1. Deprovision online package for future new users
    $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -like "*$pkg*" -or $_.PackageName -like "*$pkg*"
    }
    if ($prov) {
        Write-SyncLog "Deprovisioning AppX package: $pkg..." "ACTION" ([ConsoleColor]::Magenta)
        if (-not $DryRun) {
            $prov | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
        }
    }

    # 2. Remove package for all existing users
    $userPkgs = Get-AppxPackage -AllUsers -Name "*$pkg*" -ErrorAction SilentlyContinue
    if ($userPkgs) {
        Write-SyncLog "Removing AppX package for all users: $pkg..." "ACTION" ([ConsoleColor]::Magenta)
        if (-not $DryRun) {
            $userPkgs | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

# 4. Phase 3: Enforce Presence of Required Applications ("Not Fewer")
Write-SyncLog "[Phase 3/5] Enforcing software retention policy: ensuring required apps are present..." "INFO" ([ConsoleColor]::Yellow)

$requiredApps = @(
    @{ Name = "7-Zip"; WingetId = "7zip.7zip"; CheckReg = "*7-Zip*" },
    @{ Name = "Audacity"; WingetId = "Audacity.Audacity"; CheckReg = "*Audacity*" },
    @{ Name = "GIMP"; WingetId = "GIMP.GIMP"; CheckReg = "*GIMP*" },
    @{ Name = "Google Chrome"; WingetId = "Google.Chrome"; CheckReg = "*Google Chrome*" },
    @{ Name = "LibreOffice"; WingetId = "TheDocumentFoundation.LibreOffice"; CheckReg = "*LibreOffice*" },
    @{ Name = "Microsoft Edge"; WingetId = "Microsoft.Edge"; CheckReg = "*Microsoft Edge*" },
    @{ Name = "Microsoft Visual Studio Code"; WingetId = "Microsoft.VisualStudioCode"; CheckReg = "*Visual Studio Code*" },
    @{ Name = "Mozilla Firefox"; WingetId = "Mozilla.Firefox"; CheckReg = "*Mozilla Firefox*" },
    @{ Name = "Paint.NET"; WingetId = "dotPDN.PaintDotNet"; CheckReg = "*Paint.NET*" },
    @{ Name = "TeamViewer"; WingetId = "TeamViewer.TeamViewer"; CheckReg = "*TeamViewer*" },
    @{ Name = "VLC media player"; WingetId = "VideoLAN.VLC"; CheckReg = "*VLC media player*" }
)

$regPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

foreach ($req in $requiredApps) {
    $isInstalled = $false
    foreach ($rp in $regPaths) {
        $found = Get-ItemProperty $rp -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $req.CheckReg }
        if ($found) {
            $isInstalled = $true
            break
        }
    }

    if ($isInstalled) {
        Write-SyncLog "  [OK] $($req.Name) is installed." "INFO" ([ConsoleColor]::Green)
    } else {
        Write-SyncLog "  [MISSING] $($req.Name) not found! Installing via winget ($($req.WingetId))..." "ACTION" ([ConsoleColor]::Yellow)
        if (-not $DryRun -and $wingetExe) {
            & $wingetExe install --id $req.WingetId --exact --silent --accept-source-agreements --accept-package-agreements --scope machine
        }
    }
}

# TeamViewer Unattended Remote Support Baseline
$tvRegPaths = @("HKLM:\SOFTWARE\TeamViewer", "HKLM:\SOFTWARE\WOW6432Node\TeamViewer")
foreach ($tvPath in $tvRegPaths) {
    if (-not (Test-Path $tvPath)) {
        if (-not $DryRun) { New-Item -Path $tvPath -Force -ErrorAction SilentlyContinue | Out-Null }
    }
    if (Test-Path $tvPath) {
        if (-not $DryRun) {
            Set-ItemProperty -Path $tvPath -Name "Security_WinLogin" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $tvPath -Name "Always_Online" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $tvPath -Name "Autostart" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        }
    }
}
$tvSvc = Get-Service -Name "TeamViewer" -ErrorAction SilentlyContinue
if ($tvSvc) {
    if (-not $DryRun) {
        Set-Service -Name "TeamViewer" -StartupType Automatic -ErrorAction SilentlyContinue
        if ($tvSvc.Status -ne "Running") {
            Start-Service -Name "TeamViewer" -ErrorAction SilentlyContinue
        }
    }
    Write-SyncLog "  [OK] TeamViewer pre-configured for unattended support (Security_WinLogin = 2, Service = Automatic)." "INFO" ([ConsoleColor]::Green)
}

# 5. Phase 4: Upgrade Installed Software Packages via winget
if (-not $SkipUpgrade) {
    Write-SyncLog "[Phase 4/5] Upgrading installed software packages to the most recent version..." "INFO" ([ConsoleColor]::Yellow)
    if ($wingetExe) {
        Write-SyncLog "Triggering winget upgrade --all..." "ACTION" ([ConsoleColor]::Cyan)
        if (-not $DryRun) {
            & $wingetExe upgrade --all --accept-source-agreements --accept-package-agreements --include-unknown --silent
        }
    }

    # Trigger Microsoft Office LTSC Click-to-Run update check if installed
    $c2rPath = "$env:CommonProgramFiles\microsoft shared\ClickToRun\OfficeC2RClient.exe"
    if (Test-Path $c2rPath) {
        Write-SyncLog "Triggering Microsoft Office Click-to-Run update check..." "ACTION" ([ConsoleColor]::Cyan)
        if (-not $DryRun) {
            Start-Process -FilePath $c2rPath -ArgumentList "/update user displaylevel=false forceappshutdown=false" -NoNewWindow
        }
    }

    # Verify and apply Microsoft Office 2024 LTSC volume license activation if installed
    $osppCandidates = @(
        "$env:ProgramFiles\Microsoft Office\Office16\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office16\ospp.vbs"
    )
    $ospp = $osppCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($ospp) {
        Write-SyncLog "Checking Microsoft Office 2024 LTSC license status..." "INFO" ([ConsoleColor]::Cyan)
        try {
            $statusOut = & cscript.exe //Nologo "$ospp" /dstatus 2>&1 | Out-String
            if ($statusOut -match "---LICENSED---") {
                Write-SyncLog "  [OK] Microsoft Office is licensed and activated." "INFO" ([ConsoleColor]::Green)
            } else {
                Write-SyncLog "  Office is not fully activated. Applying MAK key and triggering activation..." "ACTION" ([ConsoleColor]::Yellow)
                if (-not $DryRun) {
                    $officeKey = "9YQNX-W4TVK-74HXJ-YDFX6-QYM2Q"
                    & cscript.exe //Nologo "$ospp" /inpkey:$officeKey 2>&1 | Out-Null
                    & cscript.exe //Nologo "$ospp" /act 2>&1 | Out-Null
                    $newStatus = & cscript.exe //Nologo "$ospp" /dstatus 2>&1 | Out-String
                    if ($newStatus -match "---LICENSED---") {
                        Write-SyncLog "  [OK] Microsoft Office activated successfully (Key: QYM2Q)." "SUCCESS" ([ConsoleColor]::Green)
                    } else {
                        Write-SyncLog "  [WARN] Office activation could not be confirmed immediately." "WARN" ([ConsoleColor]::Yellow)
                    }
                }
            }
        } catch {
            Write-SyncLog "  Notice: Error querying Office license status: $_" "WARN" ([ConsoleColor]::DarkGray)
        }
    }
} else {
    Write-SyncLog "[Phase 4/5] Package upgrade skipped via -SkipUpgrade flag." "INFO" ([ConsoleColor]::Gray)
}

# 6. Phase 5: Check and Apply Windows Updates (Software, Drivers, Firmware, Optional Updates)
if (-not $SkipWindowsUpdate) {
    Write-SyncLog "[Phase 5/5] Checking and applying Windows Updates (including hardware drivers and firmware)..." "INFO" ([ConsoleColor]::Yellow)

    try {
        # Initialize native Windows Update Session (works dynamically for any OEM/hardware)
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $updateSearcher.ServerSelection = 2 # 2 = Windows Update Online (dynamically queries Microsoft + OEM driver catalog)
        $updateSearcher.IncludePotentiallySupersededUpdates = $true

        Write-SyncLog "Querying Windows Update online for updates matching this computer's hardware..." "INFO" ([ConsoleColor]::Cyan)
        # Search criteria covers both software updates and driver/firmware updates
        $searchResult = $updateSearcher.Search("IsInstalled=0 and IsHidden=0")
        $updateCount = $searchResult.Updates.Count

        if ($updateCount -eq 0) {
            Write-SyncLog "Windows Update: No pending updates, drivers, or firmware found for this hardware." "SUCCESS" ([ConsoleColor]::Green)
        } else {
            Write-SyncLog "Found $updateCount pending update package(s) for this machine:" "INFO" ([ConsoleColor]::Yellow)
            $updatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl

            foreach ($update in $searchResult.Updates) {
                # Determine category dynamically from package metadata
                $category = if ($update.DriverClass) { "Driver: $($update.DriverClass)" } else { "Software" }
                $optional = if ($update.IsMandatory) { "Mandatory" } else { "Optional" }
                Write-SyncLog "  - [$category] [$optional] $($update.Title)" "INFO" ([ConsoleColor]::White)

                if (-not $update.EulaAccepted) {
                    $update.AcceptEula()
                }
                $updatesToDownload.Add($update) | Out-Null
            }

            if (-not $DryRun) {
                Write-SyncLog "Downloading $updateCount package(s)..." "ACTION" ([ConsoleColor]::Cyan)
                $downloader = $updateSession.CreateUpdateDownloader()
                $downloader.Updates = $updatesToDownload
                $downloadResult = $downloader.Download()
                Write-SyncLog "Download operation completed with ResultCode: $($downloadResult.ResultCode) (2=Succeeded)." "INFO" ([ConsoleColor]::Gray)

                $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
                foreach ($update in $updatesToDownload) {
                    if ($update.IsDownloaded) {
                        $updatesToInstall.Add($update) | Out-Null
                    }
                }

                if ($updatesToInstall.Count -gt 0) {
                    Write-SyncLog "Installing $($updatesToInstall.Count) update package(s)..." "ACTION" ([ConsoleColor]::Cyan)
                    $installer = $updateSession.CreateUpdateInstaller()
                    $installer.Updates = $updatesToInstall
                    $installer.ForceQuiet = $true
                    $installResult = $installer.Install()

                    Write-SyncLog "Installation completed with ResultCode: $($installResult.ResultCode) (2=Succeeded)." "SUCCESS" ([ConsoleColor]::Green)

                    if ($installResult.RebootRequired) {
                        Write-SyncLog "ATTENTION: A system reboot is required to finalize firmware and driver installations." "WARN" ([ConsoleColor]::Red)
                    } else {
                        Write-SyncLog "Windows Updates successfully applied. No immediate reboot required." "SUCCESS" ([ConsoleColor]::Green)
                    }
                } else {
                    Write-SyncLog "No packages were downloaded successfully; skipping installation." "WARN" ([ConsoleColor]::Yellow)
                }
            } else {
                Write-SyncLog "[DryRun] Would download and install $updateCount Windows Update package(s)." "INFO" ([ConsoleColor]::Gray)
            }
        }
    } catch {
        Write-SyncLog "Warning: Windows Update check encountered an error: $_" "WARN" ([ConsoleColor]::Red)
    }
} else {
    Write-SyncLog "[Phase 5/5] Windows Update check skipped via -SkipWindowsUpdate flag." "INFO" ([ConsoleColor]::Gray)
}

Write-SyncLog "==========================================================" "DONE" ([ConsoleColor]::Cyan)
Write-SyncLog "Synchronization complete." "DONE" ([ConsoleColor]::Cyan)
Write-SyncLog "Audit log saved to: $logFile" "DONE" ([ConsoleColor]::White)
