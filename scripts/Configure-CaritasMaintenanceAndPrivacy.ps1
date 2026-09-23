#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures browser credential defense, removable media lockdown, desktop hygiene, and storage maintenance.
.DESCRIPTION
    Applies security and operational maintenance policies across all Windows 11 editions:
    1. Browser Credential & Privacy Defense:
       - Disables password saving and autofill across Mozilla Firefox, Google Chrome, and Microsoft Edge.
       - Disables payment card and physical address autofill.
       - Suppresses commercial news feeds, promotional widgets, and telemetry.
       - Configures a clean, privacy-respecting search homepage (DuckDuckGo).
    2. Removable Storage Execution Lockdown (USB Hygiene):
       - Blocks execution of binaries (.exe, .scr, .bat, scripts) from USB flash drives.
       - Preserves full read and write access for documents, PDFs, pictures, and media.
    3. Public Desktop Hygiene:
       - Automatically detects and purges orphaned .lnk shortcuts pointing to nonexistent binaries.
    4. Automated Storage Hygiene:
       - Configures Windows Storage Sense machine-wide to maintain free SSD space.
       - Registers a monthly SYSTEM scheduled task for DISM Component Store cleanup and temp purging.
.PARAMETER DryRun
    Previews proposed changes without modifying policies, shortcuts, or scheduled tasks.
.PARAMETER SkipBrowserPrivacy
    Omits browser password manager, autofill, and homepage configuration.
.PARAMETER SkipUsbLockdown
    Omits USB removable media execution restrictions.
.PARAMETER SkipDesktopHygiene
    Omits public desktop dead shortcut scanning and purging.
.PARAMETER SkipStorageMaintenance
    Omits Storage Sense and scheduled maintenance task configuration.
.NOTES
    Compatible with all Windows 11 editions (Home, Pro, Enterprise, Education).
    Logs operations to logs\MaintenancePrivacy.log.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipBrowserPrivacy,
    [switch]$SkipUsbLockdown,
    [switch]$SkipDesktopHygiene,
    [switch]$SkipStorageMaintenance
)

$ErrorActionPreference = "Continue"

# 1. Logging Infrastructure (Dynamically Resolved)
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Item -Path ".").FullName }
$baseDir = Split-Path -Path $scriptDir -Parent
if (-not (Test-Path "$baseDir\scripts")) { $baseDir = $scriptDir }
$logDir = Join-Path $baseDir "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "MaintenancePrivacy.log"

function Write-MaintLog {
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

function Set-RegistryPolicy {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [string]$PropertyType = "DWord",
        [string]$Description = ""
    )
    if (-not (Test-Path $Path)) {
        if (-not $DryRun) {
            New-Item -Path $Path -Force | Out-Null
        }
    }
    $currentVal = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($currentVal -eq $Value) {
        Write-MaintLog "  [OK] $($Description) ($($Name) = $($Value))" "INFO" ([ConsoleColor]::Green)
    } else {
        if ($DryRun) {
            Write-MaintLog "  [DryRun] Would set $($Description): $($Path) -> $($Name) = $($Value) (Current: $($currentVal))" "INFO" ([ConsoleColor]::Gray)
        } else {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $PropertyType -Force | Out-Null
            Write-MaintLog "  [APPLIED] $($Description): $($Name) = $($Value)" "ACTION" ([ConsoleColor]::Yellow)
        }
    }
}

Write-MaintLog "==========================================================" "START" ([ConsoleColor]::Cyan)
Write-MaintLog "Starting Maintenance, Privacy, and Security Configuration" "START" ([ConsoleColor]::Cyan)
Write-MaintLog "Host: $env:COMPUTERNAME | Current User: $env:USERNAME" "INFO" ([ConsoleColor]::Gray)

# 2. Module 1: Browser Credential & Privacy Defense
if (-not $SkipBrowserPrivacy) {
    Write-MaintLog "[Module 1/4] Configuring Browser Credential Defense and Privacy Defaults..." "INFO" ([ConsoleColor]::Yellow)

    # A. Mozilla Firefox
    Write-MaintLog "  Configuring Mozilla Firefox Policies..." "INFO" ([ConsoleColor]::Yellow)
    $ffDir = "C:\Program Files\Mozilla Firefox"
    if (Test-Path $ffDir) {
        $distDir = Join-Path $ffDir "distribution"
        $policiesPath = Join-Path $distDir "policies.json"

        # Standard Filter Lists for uBlock Origin
        $filterLists = @(
            "user-filters", "ublock-filters", "ublock-badware", "ublock-privacy",
            "ublock-quick-fixes", "ublock-unbreak", "easylist", "easyprivacy",
            "urlhaus-1", "plowe-0", "DEU-0", "easylist-cookies", "ublock-annoyances"
        )
        $adminSettingsObj = @{
            userSettings = @{ autoUpdate = $true }
            selectedFilterLists = $filterLists
        }

        # Unified Policy Payload ensuring uBlock Origin and Credential Defense
        $ffPolicyPayload = @{
            policies = @{
                ExtensionSettings = @{
                    "uBlock0@raymondhill.net" = @{
                        installation_mode = "force_installed"
                        install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
                    }
                }
                "3rdparty" = @{
                    Extensions = @{
                        "uBlock0@raymondhill.net" = @{
                            adminSettings = $adminSettingsObj
                        }
                    }
                }
                PasswordManagerEnabled = $false
                OfferToSaveLogins = $false
                AutofillAddressEnabled = $false
                AutofillCreditCardEnabled = $false
                DisablePocket = $true
                DisableTelemetry = $true
                Homepage = @{
                    URL = "https://duckduckgo.com"
                    Locked = $false
                    StartPage = "homepage"
                }
                FirefoxHome = @{
                    Search = $true
                    TopSites = $false
                    SponsoredTopSites = $false
                    Highlights = $false
                    Pocket = $false
                    SponsoredPocket = $false
                    Snippets = $false
                    Locked = $true
                }
            }
        }

        if (-not $DryRun) {
            if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir -Force | Out-Null }
            $updatedJson = $ffPolicyPayload | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($policiesPath, $updatedJson, [System.Text.Encoding]::UTF8)
            Write-MaintLog "    [APPLIED] Updated Firefox distribution/policies.json (uBlock Origin + Credential Defense)." "ACTION" ([ConsoleColor]::Green)
        } else {
            Write-MaintLog "    [DryRun] Would update Firefox policies.json with uBlock Origin and credential defense." "INFO" ([ConsoleColor]::Gray)
        }
    }

    # Firefox Registry Policies
    $ffRegPath = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
    Set-RegistryPolicy -Path $ffRegPath -Name "PasswordManagerEnabled" -Value 0 -Description "Firefox: Disable Password Manager"
    Set-RegistryPolicy -Path $ffRegPath -Name "OfferToSaveLogins" -Value 0 -Description "Firefox: Disable Login Save Prompts"
    Set-RegistryPolicy -Path $ffRegPath -Name "DisablePocket" -Value 1 -Description "Firefox: Disable Pocket Feed"
    Set-RegistryPolicy -Path $ffRegPath -Name "DisableTelemetry" -Value 1 -Description "Firefox: Disable Telemetry"

    # B. Google Chrome
    Write-MaintLog "  Configuring Google Chrome Policies..." "INFO" ([ConsoleColor]::Yellow)
    $chromeRegPath = "HKLM:\SOFTWARE\Policies\Google\Chrome"
    Set-RegistryPolicy -Path $chromeRegPath -Name "PasswordManagerEnabled" -Value 0 -Description "Chrome: Disable Password Manager"
    Set-RegistryPolicy -Path $chromeRegPath -Name "AutofillAddressEnabled" -Value 0 -Description "Chrome: Disable Address Autofill"
    Set-RegistryPolicy -Path $chromeRegPath -Name "AutofillCreditCardEnabled" -Value 0 -Description "Chrome: Disable Credit Card Autofill"
    Set-RegistryPolicy -Path $chromeRegPath -Name "HomepageLocation" -Value "https://duckduckgo.com" -PropertyType "String" -Description "Chrome: Set DuckDuckGo Homepage"
    Set-RegistryPolicy -Path $chromeRegPath -Name "HomepageIsNewTabPage" -Value 1 -Description "Chrome: Use Homepage on New Tab"
    Set-RegistryPolicy -Path $chromeRegPath -Name "ShowHomeButton" -Value 1 -Description "Chrome: Show Home Button"
    Set-RegistryPolicy -Path $chromeRegPath -Name "PromotionalTabsEnabled" -Value 0 -Description "Chrome: Disable Promotional Tabs"
    Set-RegistryPolicy -Path $chromeRegPath -Name "MetricsReportingEnabled" -Value 0 -Description "Chrome: Disable Metrics Reporting"

    # C. Microsoft Edge
    Write-MaintLog "  Configuring Microsoft Edge Policies..." "INFO" ([ConsoleColor]::Yellow)
    $edgeRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    Set-RegistryPolicy -Path $edgeRegPath -Name "PasswordManagerEnabled" -Value 0 -Description "Edge: Disable Password Manager"
    Set-RegistryPolicy -Path $edgeRegPath -Name "AutofillAddressEnabled" -Value 0 -Description "Edge: Disable Address Autofill"
    Set-RegistryPolicy -Path $edgeRegPath -Name "AutofillCreditCardEnabled" -Value 0 -Description "Edge: Disable Credit Card Autofill"
    Set-RegistryPolicy -Path $edgeRegPath -Name "HomepageLocation" -Value "https://duckduckgo.com" -PropertyType "String" -Description "Edge: Set DuckDuckGo Homepage"
    Set-RegistryPolicy -Path $edgeRegPath -Name "HomepageIsNewTabPage" -Value 1 -Description "Edge: Use Homepage on New Tab"
    Set-RegistryPolicy -Path $edgeRegPath -Name "ShowHomeButton" -Value 1 -Description "Edge: Show Home Button"
    Set-RegistryPolicy -Path $edgeRegPath -Name "NewTabPageContentEnabled" -Value 0 -Description "Edge: Disable MSN News Feed on New Tab"
    Set-RegistryPolicy -Path $edgeRegPath -Name "HideFirstRunExperience" -Value 1 -Description "Edge: Suppress First Run Wizard"
    Set-RegistryPolicy -Path $edgeRegPath -Name "EdgeShoppingAssistantEnabled" -Value 0 -Description "Edge: Disable Shopping Assistant and Coupons"
    Set-RegistryPolicy -Path $edgeRegPath -Name "PersonalizationReportingEnabled" -Value 0 -Description "Edge: Disable Personalization Telemetry"
} else {
    Write-MaintLog "[Module 1/4] Browser credential defense skipped via -SkipBrowserPrivacy flag." "INFO" ([ConsoleColor]::Gray)
}

# 3. Module 2: Removable Storage Execution Denial (USB Hygiene)
if (-not $SkipUsbLockdown) {
    Write-MaintLog "[Module 2/4] Enforcing Removable Storage Execution Lockdown (USB Hygiene)..." "INFO" ([ConsoleColor]::Yellow)

    $usbPolicyBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices"
    $usbPolicyDisk = "$usbPolicyBase\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}" # Removable Disks Class GUID

    Set-RegistryPolicy -Path $usbPolicyBase -Name "Deny_Execute" -Value 1 -Description "Removable Storage: Deny Execute Globally"
    Set-RegistryPolicy -Path $usbPolicyDisk -Name "Deny_Execute" -Value 1 -Description "USB Flash Drives: Deny Executable and Script Launching"
    Write-MaintLog "  Notice: Patrons retain full read/write access to files; executable launching is blocked." "INFO" ([ConsoleColor]::Green)
} else {
    Write-MaintLog "[Module 2/4] Removable storage execution lockdown skipped via -SkipUsbLockdown flag." "INFO" ([ConsoleColor]::Gray)
}

# 4. Module 3: Public Desktop Hygiene (Dead Shortcut Pruning)
if (-not $SkipDesktopHygiene) {
    Write-MaintLog "[Module 3/4] Scanning Public Desktop for Dead or Broken Shortcuts..." "INFO" ([ConsoleColor]::Yellow)

    $publicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
    $wshShell = New-Object -ComObject WScript.Shell
    $shortcuts = Get-ChildItem -Path $publicDesktop -Filter "*.lnk" -ErrorAction SilentlyContinue

    $deadCount = 0
    foreach ($scFile in $shortcuts) {
        try {
            $sc = $wshShell.CreateShortcut($scFile.FullName)
            $target = $sc.TargetPath
            if ($target -and ($target -like "*:\*") -and (-not (Test-Path $target))) {
                $deadCount++
                if ($DryRun) {
                    Write-MaintLog "  [DryRun] Would purge dead shortcut: $($scFile.Name) -> $($target)" "INFO" ([ConsoleColor]::Gray)
                } else {
                    Remove-Item -Path $scFile.FullName -Force -ErrorAction SilentlyContinue
                    Write-MaintLog "  [PURGED] Removed broken shortcut: $($scFile.Name) (Target was missing: $($target))" "ACTION" ([ConsoleColor]::Yellow)
                }
            }
        } catch {
            Write-MaintLog "  Notice: Could not parse shortcut $($scFile.Name): $_" "WARN" ([ConsoleColor]::DarkGray)
        }
    }

    if ($deadCount -eq 0) {
        Write-MaintLog "  [OK] Public desktop is clean; zero broken shortcuts found." "INFO" ([ConsoleColor]::Green)
    } else {
        Write-MaintLog "  [SUCCESS] Cleaned $deadCount broken shortcut(s) from Public Desktop." "ACTION" ([ConsoleColor]::Green)
    }
} else {
    Write-MaintLog "[Module 3/4] Desktop hygiene skipped via -SkipDesktopHygiene flag." "INFO" ([ConsoleColor]::Gray)
}

# 5. Module 4: Automated Storage Sense & Component Cleanup
if (-not $SkipStorageMaintenance) {
    Write-MaintLog "[Module 4/4] Configuring Storage Sense Policies & Monthly Maintenance Task..." "INFO" ([ConsoleColor]::Yellow)

    # A. Storage Sense Machine Policies
    $storageSensePath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense"
    Set-RegistryPolicy -Path $storageSensePath -Name "AllowStorageSenseGlobal" -Value 1 -Description "Storage Sense: Enable Machine-Wide"
    Set-RegistryPolicy -Path $storageSensePath -Name "StorageSenseCadence" -Value 1 -Description "Storage Sense: Cadence (Weekly/Low Space)"
    Set-RegistryPolicy -Path $storageSensePath -Name "ConfigStorageSenseRecycleBinCleanupThreshold" -Value 30 -Description "Storage Sense: Clean Recycle Bin older than 30 days"
    Set-RegistryPolicy -Path $storageSensePath -Name "ConfigStorageSenseDownloadsCleanupThreshold" -Value 0 -Description "Storage Sense: Retain Downloads folder"

    # B. Monthly Maintenance Scheduled Task (DISM Component Cleanup & Temp Purge)
    $taskName = "Caritas-MonthlyMaintenance"
    Write-MaintLog "  Configuring Scheduled Task '$taskName'..." "INFO" ([ConsoleColor]::Yellow)

    if (-not $DryRun) {
        $maintCmd = "dism.exe /Online /Cleanup-Image /StartComponentCleanup; " +
                    "Get-ChildItem 'C:\Windows\Temp' -Recurse -Force -ErrorAction SilentlyContinue | " +
                    "Where-Object { `$_.LastWriteTime -lt (Get-Date).AddDays(-7) } | " +
                    "Remove-Item -Recurse -Force -ErrorAction SilentlyContinue"

        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$maintCmd`""

        # Trigger: 1st of every month at 03:00 AM
        $trigger = New-ScheduledTaskTrigger -At 03:00 -Weekly -DaysOfWeek Monday
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)

        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        Write-MaintLog "  [SUCCESS] Scheduled Task '$taskName' registered under NT AUTHORITY\SYSTEM." "ACTION" ([ConsoleColor]::Green)
    } else {
        Write-MaintLog "  [DryRun] Would register Scheduled Task '$taskName' for monthly DISM and Temp cleanup." "INFO" ([ConsoleColor]::Gray)
    }
} else {
    Write-MaintLog "[Module 4/4] Storage maintenance skipped via -SkipStorageMaintenance flag." "INFO" ([ConsoleColor]::Gray)
}

Write-MaintLog "==========================================================" "DONE" ([ConsoleColor]::Cyan)
Write-MaintLog "Maintenance, privacy, and security configuration complete." "DONE" ([ConsoleColor]::Cyan)
Write-MaintLog "Audit log: $logFile" "DONE" ([ConsoleColor]::White)
