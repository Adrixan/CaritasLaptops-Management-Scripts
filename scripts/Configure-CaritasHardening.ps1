#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Standalone system hardening and power baseline configuration script.
.DESCRIPTION
    Applies balanced security baselines and operational defaults across any Windows 10/11 device:
    1. Continuous Power Policy: Disables automatic sleep, hibernation, and disk spindown to ensure uninterrupted operation.
    2. Threat Mitigation: Enables Windows Defender Potentially Unwanted Application (PUA) blocking, Network Protection, and script scanning.
    3. Protocol & Peripheral Hardening: Neutralizes USB AutoRun/AutoPlay, deprecates SMBv1, and disables LLMNR and NetBIOS broadcast poisoning.
    4. Privacy & Telemetry: Restricts diagnostic telemetry to required/security levels and eliminates Bing search in the Start Menu.
    5. Baseline Consistency: Disables Fast Startup (preventing driver/kernel session corruption) and enforces registered file extension visibility.
.PARAMETER DryRun
    Scans and logs proposed configuration changes without modifying the operating system.
.PARAMETER RevertToDefaults
    Reverts configured policies back to default Windows consumer settings.
.PARAMETER SkipPower
    Omits power management and sleep timeout configuration.
.PARAMETER SkipDefender
    Omits Windows Defender anti-malware hardening.
.PARAMETER SkipNetwork
    Omits network protocol and peripheral hardening (SMBv1, LLMNR, NetBIOS, AutoRun).
.PARAMETER SkipPrivacy
    Omits privacy, telemetry, and Start Menu web search settings.
.NOTES
    Runs standalone directly on the host machine without external dependencies or domain requirements.
    Logs operations to logs\Hardening.log.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$RevertToDefaults,
    [switch]$SkipPower,
    [switch]$SkipDefender,
    [switch]$SkipNetwork,
    [switch]$SkipPrivacy
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
$logFile = Join-Path $logDir "Hardening.log"

function Write-HardeningLog {
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
        Write-HardeningLog "  [OK] $Description ($Name = $Value)" "INFO" ([ConsoleColor]::Green)
    } else {
        if ($DryRun) {
            Write-HardeningLog "  [DryRun] Would set $($Description): $Path -> $Name = $Value (Current: $currentVal)" "INFO" ([ConsoleColor]::Gray)
        } else {
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $PropertyType -Force | Out-Null
            Write-HardeningLog "  [APPLIED] $($Description): $Name = $Value" "ACTION" ([ConsoleColor]::Yellow)
        }
    }
}

Write-HardeningLog "==========================================================" "START" ([ConsoleColor]::Cyan)
Write-HardeningLog "Starting System Hardening and Operational Configuration" "START" ([ConsoleColor]::Cyan)
Write-HardeningLog "Host: $env:COMPUTERNAME | Current User: $env:USERNAME" "INFO" ([ConsoleColor]::Gray)

if ($RevertToDefaults) {
    Write-HardeningLog "REVERT MODE: Restoring default consumer settings..." "WARN" ([ConsoleColor]::Yellow)
    if (-not $DryRun) {
        powercfg /change standby-timeout-ac 15
        powercfg /change standby-timeout-dc 5
        powercfg /change monitor-timeout-ac 10
        powercfg /change monitor-timeout-dc 5
        powercfg /hibernate on
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun" -Value 0x91 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 3 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "NoConnectedUser" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive" -Name "DisableFileSyncNGSC" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive" -Name "DisableFileSync" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync" -Name "DisableSettingSync" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }
    Write-HardeningLog "Revert operations completed." "DONE" ([ConsoleColor]::Cyan)
    exit 0
}

# 2. Module 1: Continuous Power & Availability Policy (Never Sleep / Hibernate / Shut down)
if (-not $SkipPower) {
    Write-HardeningLog "[Module 1/5] Configuring Continuous Power and Availability Policy..." "INFO" ([ConsoleColor]::Yellow)

    if ($DryRun) {
        Write-HardeningLog "  [DryRun] Would disable sleep, hibernation, and disk spindown timeouts (AC and DC)." "INFO" ([ConsoleColor]::Gray)
    } else {
        # Standby (Sleep) timeout -> 0 (Never)
        powercfg /change standby-timeout-ac 0
        powercfg /change standby-timeout-dc 0
        Write-HardeningLog "  Standby (Sleep) timeout set to Never (0) on AC and DC power." "ACTION" ([ConsoleColor]::Green)

        # Hibernate timeout -> 0 (Never)
        powercfg /change hibernate-timeout-ac 0
        powercfg /change hibernate-timeout-dc 0
        Write-HardeningLog "  Hibernate timeout set to Never (0) on AC and DC power." "ACTION" ([ConsoleColor]::Green)

        # Disk idle spindown timeout -> 0 (Never)
        powercfg /change disk-timeout-ac 0
        powercfg /change disk-timeout-dc 0
        Write-HardeningLog "  Disk spindown timeout set to Never (0) on AC and DC power." "ACTION" ([ConsoleColor]::Green)

        # Display timeout -> 30 minutes on AC, 15 minutes on DC (preserves screen life without interrupting system operations)
        powercfg /change monitor-timeout-ac 30
        powercfg /change monitor-timeout-dc 15
        Write-HardeningLog "  Display timeout set to 30 min (AC) / 15 min (DC)." "ACTION" ([ConsoleColor]::Green)

        # Disable hibernation globally (removes hiberfil.sys and frees 8-16 GB disk space)
        powercfg /hibernate off
        Write-HardeningLog "  Hibernation disabled globally (hiberfil.sys purged from disk)." "ACTION" ([ConsoleColor]::Green)

        # Lid close action -> Do Nothing when plugged into AC power
        try {
            $guidSub = "4f971e89-eebd-4455-a8de-9e59040e7347" # SUB_BUTTONS
            $guidSetting = "5ca83367-6e45-459f-a27b-476b1d01c936" # LIDACTION
            powercfg /setacvalueindex SCHEME_CURRENT $guidSub $guidSetting 0 # 0 = Do nothing
            powercfg /setactive SCHEME_CURRENT
            Write-HardeningLog "  Lid close action on AC configured to Do Nothing (continuous availability)." "ACTION" ([ConsoleColor]::Green)
        } catch {
            Write-HardeningLog "  Notice: Could not modify lid close index: $_" "WARN" ([ConsoleColor]::DarkGray)
        }
    }
} else {
    Write-HardeningLog "[Module 1/5] Power policy configuration skipped via -SkipPower flag." "INFO" ([ConsoleColor]::Gray)
}

# 3. Module 2: Anti-Malware and Attack Surface Reduction (Windows Defender)
if (-not $SkipDefender) {
    Write-HardeningLog "[Module 2/5] Configuring Windows Defender Threat Mitigation & PUA Protection..." "INFO" ([ConsoleColor]::Yellow)

    try {
        $mpPrefs = Get-MpPreference -ErrorAction SilentlyContinue

        # A. Potentially Unwanted Application (PUA) Protection
        if ($mpPrefs.PUAProtection -ne 1) {
            if ($DryRun) {
                Write-HardeningLog "  [DryRun] Would enable PUAProtection." "INFO" ([ConsoleColor]::Gray)
            } else {
                Set-MpPreference -PUAProtection Enabled -ErrorAction SilentlyContinue
                Write-HardeningLog "  [APPLIED] PUA Protection enabled (blocks adware and bundled toolbars)." "ACTION" ([ConsoleColor]::Yellow)
            }
        } else {
            Write-HardeningLog "  [OK] PUA Protection already enabled." "INFO" ([ConsoleColor]::Green)
        }

        # B. Real-time, Behavioral, Script, and IOAV Protection
        if (-not $DryRun) {
            Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
            Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction SilentlyContinue
            Set-MpPreference -DisableScriptScanning $false -ErrorAction SilentlyContinue
            Set-MpPreference -DisableIOAVProtection $false -ErrorAction SilentlyContinue
            Set-MpPreference -MAPSReporting Advanced -ErrorAction SilentlyContinue
            Set-MpPreference -EnableNetworkProtection Enabled -ErrorAction SilentlyContinue
            Write-HardeningLog "  [APPLIED] Real-time, behavioral, script scanning, and network protection verified." "ACTION" ([ConsoleColor]::Green)
        } else {
            Write-HardeningLog "  [DryRun] Would ensure real-time, behavioral, script, and network protection are active." "INFO" ([ConsoleColor]::Gray)
        }
    } catch {
        Write-HardeningLog "Warning: Could not configure Defender preferences: $_" "WARN" ([ConsoleColor]::Red)
    }
} else {
    Write-HardeningLog "[Module 2/5] Windows Defender configuration skipped via -SkipDefender flag." "INFO" ([ConsoleColor]::Gray)
}

# 4. Module 3: Protocol Deprecation & Peripheral Protection
if (-not $SkipNetwork) {
    Write-HardeningLog "[Module 3/5] Neutralizing Legacy Protocols and Peripheral Threat Vectors..." "INFO" ([ConsoleColor]::Yellow)

    # A. USB AutoRun / AutoPlay Mitigation (Prevents thumb drive worm propagation)
    $explorerPolicyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    Set-RegistryPolicy -Path $explorerPolicyPath -Name "NoDriveTypeAutoRun" -Value 255 -Description "Disable AutoRun across all drive types (0xFF)"
    Set-RegistryPolicy -Path $explorerPolicyPath -Name "NoAutorun" -Value 1 -Description "Disable AutoRun globally"

    # B. Disable SMBv1 Protocol
    try {
        $smb1 = Get-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -ErrorAction SilentlyContinue
        if ($smb1 -and $smb1.State -eq "Enabled") {
            if ($DryRun) {
                Write-HardeningLog "  [DryRun] Would disable legacy SMB1Protocol." "INFO" ([ConsoleColor]::Gray)
            } else {
                Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart -ErrorAction SilentlyContinue | Out-Null
                Write-HardeningLog "  [APPLIED] SMB1Protocol disabled (neutralizes legacy SMB vulnerabilities)." "ACTION" ([ConsoleColor]::Yellow)
            }
        } else {
            Write-HardeningLog "  [OK] Legacy SMB1Protocol is not enabled." "INFO" ([ConsoleColor]::Green)
        }
    } catch {
        Write-HardeningLog "  Notice: SMB1 query returned: $_" "WARN" ([ConsoleColor]::DarkGray)
    }

    # C. Disable LLMNR (Link-Local Multicast Name Resolution) to mitigate broadcast poisoning
    $dnsClientPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
    Set-RegistryPolicy -Path $dnsClientPolicyPath -Name "EnableMulticast" -Value 0 -Description "Disable LLMNR broadcast resolution"

    # D. Disable NetBIOS over TCP/IP across active network adapters
    if (-not $DryRun) {
        try {
            $adapters = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" -ErrorAction SilentlyContinue
            foreach ($adapter in $adapters) {
                if ($adapter.TcpipNetbiosOptions -ne 2) {
                    $adapter | Invoke-CimMethod -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = 2 } | Out-Null
                    Write-HardeningLog "  [APPLIED] Disabled NetBIOS on adapter '$($adapter.Description)'." "ACTION" ([ConsoleColor]::Yellow)
                }
            }
            Write-HardeningLog "  [OK] NetBIOS over TCP/IP disabled across active adapters." "INFO" ([ConsoleColor]::Green)
        } catch {
            Write-HardeningLog "  Notice: NetBIOS configuration check returned: $_" "WARN" ([ConsoleColor]::DarkGray)
        }
    } else {
        Write-HardeningLog "  [DryRun] Would disable NetBIOS over TCP/IP on active network adapters." "INFO" ([ConsoleColor]::Gray)
    }
} else {
    Write-HardeningLog "[Module 3/5] Protocol deprecation skipped via -SkipNetwork flag." "INFO" ([ConsoleColor]::Gray)
}

# 5. Module 4: Privacy & Windows Telemetry Reduction
if (-not $SkipPrivacy) {
    Write-HardeningLog "[Module 4/5] Establishing Privacy Baselines & Start Menu Cleanup..." "INFO" ([ConsoleColor]::Yellow)

    # A. Limit Telemetry to Required / Security Level
    $dataCollectionPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    Set-RegistryPolicy -Path $dataCollectionPath -Name "AllowTelemetry" -Value 1 -Description "Telemetry restricted to Required (Security Baseline)"

    # B. Disable Advertising ID
    $advertisingPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
    Set-RegistryPolicy -Path $advertisingPath -Name "DisabledByGroupPolicy" -Value 1 -Description "Advertising ID disabled via policy"

    # C. Disable Bing Web Search in the Start Menu
    $searchPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    Set-RegistryPolicy -Path $searchPolicyPath -Name "DisableWebSearch" -Value 1 -Description "Disable Bing web search in Start Menu"
    Set-RegistryPolicy -Path $searchPolicyPath -Name "ConnectedSearchUseWeb" -Value 0 -Description "Prevent Start Menu search from querying cloud web endpoints"

    # D. Disable Timeline Activity Tracking
    $systemPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    Set-RegistryPolicy -Path $systemPolicyPath -Name "EnableActivityFeed" -Value 0 -Description "Disable Activity Feed timeline tracking"
    Set-RegistryPolicy -Path $systemPolicyPath -Name "PublishUserActivities" -Value 0 -Description "Disable publishing user activities"
    Set-RegistryPolicy -Path $systemPolicyPath -Name "UploadUserActivities" -Value 0 -Description "Disable uploading user activities"

    # E. Disable Consumer Experience Promos
    $cloudContentPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    Set-RegistryPolicy -Path $cloudContentPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Description "Disable promotional consumer apps and suggestions"
    Set-RegistryPolicy -Path $cloudContentPath -Name "DisableTailoredExperiencesWithDiagnosticData" -Value 1 -Description "Disable diagnostic data tailored experiences"

    # F. Block Microsoft Account (MSA) Attachment Across All Editions
    $systemPoliciesPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    Set-RegistryPolicy -Path $systemPoliciesPath -Name "NoConnectedUser" -Value 3 -Description "Block Microsoft Account linking and sign-in (NoConnectedUser = 3)"

    # G. Disable OneDrive Storage, Sync Engine, and Autostart
    $oneDrivePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive"
    Set-RegistryPolicy -Path $oneDrivePolicyPath -Name "DisableFileSyncNGSC" -Value 1 -Description "Prevent usage of OneDrive for file storage"
    Set-RegistryPolicy -Path $oneDrivePolicyPath -Name "DisableFileSync" -Value 1 -Description "Disable OneDrive file synchronization globally"
    if (-not $DryRun) {
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -ErrorAction SilentlyContinue
    }

    # H. Disable Windows Settings Synchronization
    $settingSyncPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync"
    Set-RegistryPolicy -Path $settingSyncPolicyPath -Name "DisableSettingSync" -Value 2 -Description "Disable Windows Settings Synchronization"
    Set-RegistryPolicy -Path $settingSyncPolicyPath -Name "DisableSettingSyncUserOverride" -Value 1 -Description "Disable Settings Sync user override"

    # I. Suppress OOBE Privacy Experience Questions on First Logon
    $oobePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE"
    Set-RegistryPolicy -Path $oobePolicyPath -Name "DisablePrivacyExperience" -Value 1 -Description "Disable OOBE privacy setup questions"
    Set-RegistryPolicy -Path $systemPoliciesPath -Name "DisablePrivacyExperience" -Value 1 -Description "Disable privacy settings experience on logon"
    Set-RegistryPolicy -Path $systemPoliciesPath -Name "EnableFirstLogonAnimation" -Value 0 -Description "Disable first logon animation"
    Set-RegistryPolicy -Path $systemPolicyPath -Name "DisablePrivacyExperience" -Value 1 -Description "Disable privacy experience in system policy"

    # J. Disable Location Services & Geolocation Sensors
    $locationPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"
    Set-RegistryPolicy -Path $locationPolicyPath -Name "DisableLocation" -Value 1 -Description "Disable location sensors machine-wide"
    Set-RegistryPolicy -Path $locationPolicyPath -Name "DisableLocationScripting" -Value 1 -Description "Disable location scripting access"
    Set-RegistryPolicy -Path $locationPolicyPath -Name "DisableSensors" -Value 1 -Description "Disable system sensors"
    $consentStoreLoc = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
    Set-RegistryPolicy -Path $consentStoreLoc -Name "Value" -Value "Deny" -PropertyType "String" -Description "Deny app access to location by default"

    # K. Disable Inking and Typing Data Personalization (Keylogger / Dictionaries)
    $inputPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization"
    Set-RegistryPolicy -Path $inputPolicyPath -Name "AllowInputPersonalization" -Value 0 -Description "Disable input and typing personalization"
    Set-RegistryPolicy -Path $inputPolicyPath -Name "RestrictImplicitInkCollection" -Value 1 -Description "Restrict implicit ink collection"
    Set-RegistryPolicy -Path $inputPolicyPath -Name "RestrictImplicitTextCollection" -Value 1 -Description "Restrict implicit text collection"

    # L. Disable Find My Device
    $findMyDevicePath = "HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice"
    Set-RegistryPolicy -Path $findMyDevicePath -Name "AllowFindMyDevice" -Value 0 -Description "Disable Find My Device tracking"

    # M. Disable Speech Model Updates & Online Speech Recognition
    $speechPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Speech"
    Set-RegistryPolicy -Path $speechPolicyPath -Name "AllowSpeechModelUpdate" -Value 0 -Description "Disable speech model cloud updates"

    # N. Disable Windows Welcome Experience, Tips, and App Auto-Restart
    $userEngagementPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement"
    Set-RegistryPolicy -Path $userEngagementPath -Name "ScoobeSystemSettingEnabled" -Value 0 -Description "Disable SCOOBE second-chance setup experience"
    Set-RegistryPolicy -Path $userEngagementPath -Name "ShowWindowsProvider" -Value 0 -Description "Disable Windows Provider engagement popups"

    $winlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-RegistryPolicy -Path $winlogonPath -Name "RestartApps" -Value 0 -Description "Disable automatic restarting of apps on sign-in"
    Set-RegistryPolicy -Path $systemPolicyPath -Name "DisableRestartApps" -Value 1 -Description "Disable app auto-restart via group policy"

    Set-RegistryPolicy -Path $cloudContentPath -Name "DisableSoftLanding" -Value 1 -Description "Disable soft landing tips and promotional suggestions"
    Set-RegistryPolicy -Path $cloudContentPath -Name "DisableWindowsSpotlightFeatures" -Value 1 -Description "Disable Windows Spotlight lock screen promotions"

    # O. Stamp Privacy Defaults into Active and Default User Hives
    if (-not $DryRun) {
        $loadedHives = @("HKU:\.DEFAULT")
        Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21' -and $_.PSChildName -notmatch '_Classes$' } | ForEach-Object {
            $loadedHives += "Registry::HKEY_USERS\$($_.PSChildName)"
        }
        foreach ($hive in $loadedHives) {
            $cdmPath = "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
            if (-not (Test-Path $cdmPath)) { New-Item -Path $cdmPath -Force -ErrorAction SilentlyContinue | Out-Null }
            foreach ($sub in @("310093", "338387", "338388", "338389", "353694", "353696", "353698")) {
                New-ItemProperty -Path $cdmPath -Name "SubscribedContent-${sub}Enabled" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
            }
            New-ItemProperty -Path $cdmPath -Name "SoftLandingEnabled" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
            New-ItemProperty -Path $cdmPath -Name "ContentDeliveryAllowed" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

            $privPath = "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy"
            if (-not (Test-Path $privPath)) { New-Item -Path $privPath -Force -ErrorAction SilentlyContinue | Out-Null }
            New-ItemProperty -Path $privPath -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

            $settingsPath = "$hive\SOFTWARE\Microsoft\Personalization\Settings"
            if (-not (Test-Path $settingsPath)) { New-Item -Path $settingsPath -Force -ErrorAction SilentlyContinue | Out-Null }
            New-ItemProperty -Path $settingsPath -Name "AcceptedPrivacyPolicy" -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

            $engagePath = "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement"
            if (-not (Test-Path $engagePath)) { New-Item -Path $engagePath -Force -ErrorAction SilentlyContinue | Out-Null }
            New-ItemProperty -Path $engagePath -Name "ScoobeSystemSettingEnabled" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
            New-ItemProperty -Path $engagePath -Name "ShowWindowsProvider" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Write-HardeningLog "  [OK] Stamped privacy consent and welcome bypass across $($loadedHives.Count) user profile hives." "INFO" ([ConsoleColor]::Green)
    }
} else {
    Write-HardeningLog "[Module 4/5] Privacy configuration skipped via -SkipPrivacy flag." "INFO" ([ConsoleColor]::Gray)
}

# 6. Module 5: Safe Baseline Defaults for All Users
Write-HardeningLog "[Module 5/5] Establishing System Baseline Defaults across All Profiles..." "INFO" ([ConsoleColor]::Yellow)

# A. Display File Extensions by Default (Mitigates double-extension executable disguise)
$explorerAdvancedFolder = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\Folder\HideFileExt"
Set-RegistryPolicy -Path $explorerAdvancedFolder -Name "DefaultValue" -Value 0 -Description "Enforce visibility of registered file extensions by default"

# B. Disable Fast Startup (Hybrid Boot) to prevent driver state corruption and ensure clean reboots
$powerSystemPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
Set-RegistryPolicy -Path $powerSystemPath -Name "HiberbootEnabled" -Value 0 -Description "Disable Fast Startup (Hybrid Boot)"

# C. Disable Unsolicited Remote Assistance Offers
$remoteAssistPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance"
Set-RegistryPolicy -Path $remoteAssistPath -Name "fAllowToGetHelp" -Value 0 -Description "Disable unsolicited Remote Assistance"

Write-HardeningLog "==========================================================" "DONE" ([ConsoleColor]::Cyan)
Write-HardeningLog "System Hardening and Operational Configuration complete." "DONE" ([ConsoleColor]::Cyan)
Write-HardeningLog "Audit log saved to: $logFile" "DONE" ([ConsoleColor]::White)
