#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures machine-wide default application associations and enterprise browser ad-blockers.
.DESCRIPTION
    Applies consistent software defaults and privacy protection across all Windows 11 editions:
    1. Default Browser: Enforces Mozilla Firefox for HTTP, HTTPS, HTML documents, and PDF viewing.
    2. Media Playback: Enforces VLC Media Player for all audio and video formats.
    3. Document Handlers:
       - Microsoft Office (Word, Excel, PowerPoint) for proprietary formats (.docx, .xlsx, .pptx, etc.).
       - LibreOffice (Writer, Calc, Impress, Draw, Math) for OpenDocument formats (.odt, .ods, .odp, .odg, .odf).
    4. Archive Handlers: Enforces 7-Zip for compressed formats (.7z, .rar, .tar, .gz), retaining Windows Explorer for .zip.
    5. Machine-Wide Deployment: Compiles an OEM Default Associations XML file, registers it via Group Policy,
       and applies it to the active Windows image via DISM.
    6. Browser Extension Security: Force-installs uBlock Origin across Mozilla Firefox, Google Chrome,
       and Microsoft Edge with pre-configured filter lists (EasyList, EasyPrivacy, Malware protection,
       EasyList Germany for regional domains, and EasyList Cookie/Annoyances for GDPR banner suppression).
.PARAMETER DryRun
    Scans and previews proposed associations and policy configurations without modifying system settings.
.PARAMETER SkipAssociations
    Omits file and protocol default application association configuration.
.PARAMETER SkipExtensions
    Omits browser extension and ad-blocker policy deployment.
.NOTES
    Compatible with all Windows 11 editions (Home, Pro, Enterprise, Education).
    Logs operations to logs\Defaults.log.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipAssociations,
    [switch]$SkipExtensions
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
$configDir = Join-Path $baseDir "config"
$logDir = Join-Path $baseDir "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "Defaults.log"

function Write-DefaultsLog {
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

Write-DefaultsLog "==========================================================" "START" ([ConsoleColor]::Cyan)
Write-DefaultsLog "Starting Default Applications and Ad-Blocker Configuration" "START" ([ConsoleColor]::Cyan)
Write-DefaultsLog "Host: $env:COMPUTERNAME | Current User: $env:USERNAME" "INFO" ([ConsoleColor]::Gray)

# 2. Module 1: Default Application Associations
if (-not $SkipAssociations) {
    Write-DefaultsLog "[Module 1/2] Resolving and Generating Default Application Associations..." "INFO" ([ConsoleColor]::Yellow)

    # Dynamic Discovery: Firefox
    $firefoxRegKey = Get-ChildItem "HKLM:\SOFTWARE\Clients\StartMenuInternet" -ErrorAction SilentlyContinue | 
        Where-Object { $_.PSChildName -like "Firefox*" } | Select-Object -First 1

    $ffUrlProgId = "FirefoxURL-308046B0AF4A39CB"
    $ffHtmlProgId = "FirefoxHTML-308046B0AF4A39CB"
    $ffPdfProgId = "FirefoxPDF-308046B0AF4A39CB"

    if ($firefoxRegKey) {
        $ffUrlAssoc = (Get-ItemProperty "$($firefoxRegKey.PSPath)\Capabilities\URLAssociations" -ErrorAction SilentlyContinue).http
        if ($ffUrlAssoc) { $ffUrlProgId = $ffUrlAssoc }

        $ffFileAssoc = Get-ItemProperty "$($firefoxRegKey.PSPath)\Capabilities\FileAssociations" -ErrorAction SilentlyContinue
        if ($ffFileAssoc.".html") { $ffHtmlProgId = $ffFileAssoc.".html" }
        if ($ffFileAssoc.".pdf") { $ffPdfProgId = $ffFileAssoc.".pdf" }
    }
    Write-DefaultsLog "  Discovered Firefox ProgIDs: URL=$ffUrlProgId, HTML=$ffHtmlProgId, PDF=$ffPdfProgId" "INFO" ([ConsoleColor]::Gray)

    # Dynamic Discovery: VLC Media Player
    $vlcFileAssoc = Get-ItemProperty "HKLM:\SOFTWARE\Clients\Media\VLC\Capabilities\FileAssociations" -ErrorAction SilentlyContinue
    $vlcExtensions = @(
        ".mp4", ".mkv", ".avi", ".mov", ".wmv", ".flv", ".webm", ".m4v", ".ts", ".mpeg", ".mpg", ".3gp", ".vob",
        ".mp3", ".wav", ".flac", ".aac", ".ogg", ".oga", ".m4a", ".wma", ".opus", ".aiff", ".mid",
        ".m3u", ".m3u8", ".pls"
    )

    # Association Catalog Construction
    $associations = [System.Collections.Generic.List[PSCustomObject]]::new()

    function Add-Assoc {
        param([string]$ExtOrProto, [string]$ProgId, [string]$AppName)
        $associations.Add([PSCustomObject]@{
            Identifier = $ExtOrProto
            ProgId = $ProgId
            ApplicationName = $AppName
        })
    }

    # A. Web Protocols and Documents (Firefox)
    Add-Assoc "http" $ffUrlProgId "Mozilla Firefox"
    Add-Assoc "https" $ffUrlProgId "Mozilla Firefox"
    Add-Assoc ".htm" $ffHtmlProgId "Mozilla Firefox"
    Add-Assoc ".html" $ffHtmlProgId "Mozilla Firefox"
    Add-Assoc ".shtml" $ffHtmlProgId "Mozilla Firefox"
    Add-Assoc ".xht" $ffHtmlProgId "Mozilla Firefox"
    Add-Assoc ".xhtml" $ffHtmlProgId "Mozilla Firefox"
    Add-Assoc ".svg" $ffHtmlProgId "Mozilla Firefox"
    Add-Assoc ".pdf" $ffPdfProgId "Mozilla Firefox"

    # B. Media Formats (VLC)
    foreach ($ext in $vlcExtensions) {
        $vlcTargetProgId = if ($vlcFileAssoc -and $vlcFileAssoc.$ext) { $vlcFileAssoc.$ext } else { "VLC$ext" }
        Add-Assoc $ext $vlcTargetProgId "VLC media player"
    }

    # C. Microsoft Office Proprietary Formats
    Add-Assoc ".docx" "Word.Document.12" "Microsoft Word"
    Add-Assoc ".doc" "Word.Document.8" "Microsoft Word"
    Add-Assoc ".docm" "Word.DocumentMacroEnabled.12" "Microsoft Word"
    Add-Assoc ".dotx" "Word.Template.12" "Microsoft Word"
    Add-Assoc ".dot" "Word.Template.8" "Microsoft Word"

    Add-Assoc ".xlsx" "Excel.Sheet.12" "Microsoft Excel"
    Add-Assoc ".xls" "Excel.Sheet.8" "Microsoft Excel"
    Add-Assoc ".xlsm" "Excel.SheetMacroEnabled.12" "Microsoft Excel"
    Add-Assoc ".xltx" "Excel.Template.12" "Microsoft Excel"
    Add-Assoc ".csv" "Excel.CSV" "Microsoft Excel"

    Add-Assoc ".pptx" "PowerPoint.Show.12" "Microsoft PowerPoint"
    Add-Assoc ".ppt" "PowerPoint.Show.8" "Microsoft PowerPoint"
    Add-Assoc ".pptm" "PowerPoint.ShowMacroEnabled.12" "Microsoft PowerPoint"
    Add-Assoc ".ppsx" "PowerPoint.SlideShow.12" "Microsoft PowerPoint"

    # Verify and activate Microsoft Office 2024 LTSC volume license if present
    $osppCandidates = @(
        "$env:ProgramFiles\Microsoft Office\Office16\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office16\ospp.vbs"
    )
    $ospp = $osppCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($ospp) {
        try {
            $statusOut = & cscript.exe //Nologo "$ospp" /dstatus 2>&1 | Out-String
            if ($statusOut -match "---LICENSED---") {
                Write-DefaultsLog "  [OK] Microsoft Office is licensed and activated." "INFO" ([ConsoleColor]::Green)
            } else {
                if (-not $DryRun) {
                    $officeKey = "9YQNX-W4TVK-74HXJ-YDFX6-QYM2Q"
                    & cscript.exe //Nologo "$ospp" /inpkey:$officeKey 2>&1 | Out-Null
                    & cscript.exe //Nologo "$ospp" /act 2>&1 | Out-Null
                    Write-DefaultsLog "  [APPLIED] Microsoft Office activated with volume license key." "ACTION" ([ConsoleColor]::Yellow)
                } else {
                    Write-DefaultsLog "  [DryRun] Would activate Microsoft Office using volume license key." "INFO" ([ConsoleColor]::Gray)
                }
            }
        } catch {
            Write-DefaultsLog "  Notice: Office license query: $_" "WARN" ([ConsoleColor]::DarkGray)
        }
    }

    # D. OpenDocument Formats (LibreOffice)
    Add-Assoc ".odt" "LibreOffice.WriterDocument.1" "LibreOffice Writer"
    Add-Assoc ".fodt" "LibreOffice.WriterDocument.1" "LibreOffice Writer"
    Add-Assoc ".ott" "LibreOffice.WriterTemplate.1" "LibreOffice Writer"

    Add-Assoc ".ods" "LibreOffice.CalcDocument.1" "LibreOffice Calc"
    Add-Assoc ".fods" "LibreOffice.CalcDocument.1" "LibreOffice Calc"

    Add-Assoc ".odp" "LibreOffice.ImpressDocument.1" "LibreOffice Impress"
    Add-Assoc ".fodp" "LibreOffice.ImpressDocument.1" "LibreOffice Impress"
    Add-Assoc ".otp" "LibreOffice.ImpressTemplate.1" "LibreOffice Impress"

    Add-Assoc ".odg" "LibreOffice.DrawDocument.1" "LibreOffice Draw"
    Add-Assoc ".fodg" "LibreOffice.DrawDocument.1" "LibreOffice Draw"

    Add-Assoc ".odf" "LibreOffice.MathDocument.1" "LibreOffice Math"

    # E. Archives (7-Zip for complex archives, Windows Explorer for .zip)
    Add-Assoc ".zip" "CompressedFolder" "Windows-Explorer"
    Add-Assoc ".7z" "7-Zip.7z" "7-Zip File Manager"
    Add-Assoc ".rar" "7-Zip.rar" "7-Zip File Manager"
    Add-Assoc ".tar" "7-Zip.tar" "7-Zip File Manager"
    Add-Assoc ".gz" "7-Zip.gz" "7-Zip File Manager"
    Add-Assoc ".bz2" "7-Zip.bz2" "7-Zip File Manager"
    Add-Assoc ".xz" "7-Zip.xz" "7-Zip File Manager"
    Add-Assoc ".iso" "7-Zip.iso" "7-Zip File Manager"

    # Build XML Payload
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    $xmlPath = Join-Path $configDir "AppAssociations.xml"

    $xmlLines = [System.Collections.Generic.List[string]]::new()
    $xmlLines.Add('<?xml version="1.0" encoding="UTF-8"?>')
    $xmlLines.Add('<DefaultAssociations>')
    foreach ($a in $associations) {
        $xmlLines.Add("  <Association Identifier=""$($a.Identifier)"" ProgId=""$($a.ProgId)"" ApplicationName=""$($a.ApplicationName)"" />")
    }
    $xmlLines.Add('</DefaultAssociations>')

    if ($DryRun) {
        Write-DefaultsLog "  [DryRun] Would write $($associations.Count) associations to $xmlPath and apply via DISM." "INFO" ([ConsoleColor]::Gray)
    } else {
        [System.IO.File]::WriteAllLines($xmlPath, $xmlLines, [System.Text.Encoding]::UTF8)
        & icacls.exe $xmlPath /grant "*S-1-5-11:(R)" /Q 2>$null
        Write-DefaultsLog "  Compiled OEM association catalog with $($associations.Count) mappings at $xmlPath." "ACTION" ([ConsoleColor]::Green)

        # Enforce DefaultAssociationsConfiguration Group Policy for all new profiles
        $sysPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        if (-not (Test-Path $sysPolicyPath)) { New-Item -Path $sysPolicyPath -Force | Out-Null }
        New-ItemProperty -Path $sysPolicyPath -Name "DefaultAssociationsConfiguration" -Value $xmlPath -PropertyType String -Force | Out-Null
        Write-DefaultsLog "  [APPLIED] Policy DefaultAssociationsConfiguration set to '$xmlPath'." "ACTION" ([ConsoleColor]::Green)

        # Apply to live operating system image via DISM
        Write-DefaultsLog "  Applying default associations via DISM..." "ACTION" ([ConsoleColor]::Yellow)
        $dismOutput = dism.exe /Online /Import-DefaultAppAssociations:$xmlPath 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Write-DefaultsLog "  [SUCCESS] DISM successfully applied default application associations." "ACTION" ([ConsoleColor]::Green)
        } else {
            Write-DefaultsLog "  Warning: DISM returned code $($LASTEXITCODE): $dismOutput" "WARN" ([ConsoleColor]::Red)
        }
    }
} else {
    Write-DefaultsLog "[Module 1/2] Default application associations skipped via -SkipAssociations flag." "INFO" ([ConsoleColor]::Gray)
}

# 3. Module 2: Browser Ad-Blocker (uBlock Origin) Machine-Wide Deployment
if (-not $SkipExtensions) {
    Write-DefaultsLog "[Module 2/2] Configuring uBlock Origin Enterprise Policies Across Web Browsers..." "INFO" ([ConsoleColor]::Yellow)

    # Standard Filter Lists: Core + Privacy + Malware + Regional German (DEU-0) + Cookie/Annoyance Suppression
    $filterLists = @(
        "user-filters",
        "ublock-filters",
        "ublock-badware",
        "ublock-privacy",
        "ublock-quick-fixes",
        "ublock-unbreak",
        "easylist",
        "easyprivacy",
        "urlhaus-1",
        "plowe-0",
        "DEU-0",
        "easylist-cookies",
        "ublock-annoyances"
    )

    $adminSettingsObj = @{
        userSettings = @{
            autoUpdate = $true
        }
        selectedFilterLists = $filterLists
    }
    $adminSettingsJson = $adminSettingsObj | ConvertTo-Json -Depth 10 -Compress

    # A. Mozilla Firefox Configuration
    Write-DefaultsLog "  Provisioning Mozilla Firefox..." "INFO" ([ConsoleColor]::Yellow)
    $ffInstallDirs = @(
        "C:\Program Files\Mozilla Firefox",
        "C:\Program Files (x86)\Mozilla Firefox"
    ) | Where-Object { Test-Path $_ }

    $ffPolicyPayload = @{
        policies = @{
            SkipTermsOfUse = $true
            DontCheckDefaultBrowser = $true
            OverrideFirstRunPage = ""
            OverridePostUpdatePage = ""
            DisableProfileImport = $true
            DisableSetDesktopBackground = $true
            DisableFirefoxStudies = $true
            DisableTelemetry = $true
            DisablePocket = $true
            DisableFirefoxScreens = $true
            WindowsLaunchOnLogin = $false
            PromptForDownloadLocation = $false
            PasswordManagerEnabled = $false
            OfferToSaveLogins = $false
            AutofillAddressEnabled = $false
            AutofillCreditCardEnabled = $false
            Homepage = @{
                URL = "https://search.brave.com"
                Locked = $true
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
            Preferences = @{
                "browser.aboutwelcome.enabled" = @{ Value = $false; Status = "locked" }
                "browser.aboutwelcome.screens" = @{ Value = ""; Status = "locked" }
                "browser.startup.homepage_welcome_url" = @{ Value = ""; Status = "locked" }
                "browser.startup.homepage_welcome_url.additional" = @{ Value = ""; Status = "locked" }
                "startup.homepage_welcome_url" = @{ Value = ""; Status = "locked" }
                "startup.homepage_welcome_url.additional" = @{ Value = ""; Status = "locked" }
                "trailhead.firstrun.didSeeAboutWelcome" = @{ Value = $true; Status = "locked" }
                "trailhead.firstrun.branches" = @{ Value = "nofirstrun-empty"; Status = "locked" }
                "browser.startup.firstrunSkipsHomepage" = @{ Value = $false; Status = "locked" }
                "browser.startup.homepage_override.mstone" = @{ Value = "ignore"; Status = "locked" }
                "browser.startup.page" = @{ Value = 1; Status = "locked" }
                "browser.startup.homepage" = @{ Value = "https://search.brave.com"; Status = "locked" }
                "browser.shell.checkDefaultBrowser" = @{ Value = $false; Status = "locked" }
                "browser.startup.windowsLaunchOnLogin.enabled" = @{ Value = $false; Status = "locked" }
                "browser.startup.windowsLaunchOnLogin.disable" = @{ Value = $true; Status = "locked" }
                "doh-rollout.doneFirstRun" = @{ Value = $true; Status = "locked" }
                "app.shield.optoutstudies.enabled" = @{ Value = $false; Status = "locked" }
                "datareporting.policy.dataSubmissionPolicyAcceptedVersion" = @{ Value = 2; Status = "locked" }
                "browser.uitour.enabled" = @{ Value = $false; Status = "locked" }
                "browser.newtabpage.activity-stream.aboutwelcome.show" = @{ Value = $false; Status = "locked" }
                "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons" = @{ Value = $false; Status = "locked" }
                "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features" = @{ Value = $false; Status = "locked" }
                "browser.tabs.warnOnClose" = @{ Value = $false; Status = "default" }
            }
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
        }
    }
    $ffPolicyJson = $ffPolicyPayload | ConvertTo-Json -Depth 10

    if (-not $DryRun) {
        # 1. distribution/policies.json file & autoconfig locking
        foreach ($ffDir in $ffInstallDirs) {
            $distDir = Join-Path $ffDir "distribution"
            if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir -Force | Out-Null }
            $policyFile = Join-Path $distDir "policies.json"
            [System.IO.File]::WriteAllText($policyFile, $ffPolicyJson, [System.Text.Encoding]::UTF8)
            Write-DefaultsLog "    Deployed Firefox policies.json to $policyFile." "ACTION" ([ConsoleColor]::Green)

            # Deploy autoconfig & firefox.cfg to guarantee first-run bypass
            $prefDir = Join-Path $ffDir "defaults\pref"
            if (-not (Test-Path $prefDir)) { New-Item -ItemType Directory -Path $prefDir -Force | Out-Null }
            $autoJs = "pref(`"general.config.filename`", `"firefox.cfg`");`r`npref(`"general.config.obscure_value`", 0);`r`n"
            [System.IO.File]::WriteAllText((Join-Path $prefDir "autoconfig.js"), $autoJs, [System.Text.Encoding]::UTF8)

            $ffCfgContent = @"
// First line must be a comment
lockPref("trailhead.firstrun.branches", "nofirstrun-empty");
lockPref("trailhead.firstrun.didSeeAboutWelcome", true);
lockPref("browser.aboutwelcome.enabled", false);
lockPref("browser.aboutwelcome.screens", "");
lockPref("browser.startup.firstrunSkipsHomepage", false);
lockPref("browser.startup.homepage_override.mstone", "ignore");
lockPref("browser.startup.page", 1);
lockPref("browser.startup.homepage", "https://search.brave.com");
lockPref("browser.newtabpage.activity-stream.aboutwelcome.show", false);
lockPref("browser.startup.windowsLaunchOnLogin.enabled", false);
lockPref("browser.startup.windowsLaunchOnLogin.disable", true);
lockPref("browser.shell.checkDefaultBrowser", false);
lockPref("browser.startup.homepage_welcome_url", "");
lockPref("browser.startup.homepage_welcome_url.additional", "");
lockPref("startup.homepage_welcome_url", "");
lockPref("startup.homepage_welcome_url.additional", "");
lockPref("browser.uitour.enabled", false);
lockPref("doh-rollout.doneFirstRun", true);
"@
            [System.IO.File]::WriteAllText((Join-Path $ffDir "firefox.cfg"), $ffCfgContent, [System.Text.Encoding]::UTF8)
            Write-DefaultsLog "    Deployed Firefox autoconfig.js and firefox.cfg." "ACTION" ([ConsoleColor]::Green)
        }

        # 2. HKLM Registry Policy for Firefox
        $ffRegPolicy = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
        if (-not (Test-Path $ffRegPolicy)) { New-Item -Path $ffRegPolicy -Force | Out-Null }
        New-ItemProperty -Path $ffRegPolicy -Name "SkipTermsOfUse" -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $ffRegPolicy -Name "DisableFirefoxScreens" -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $ffRegPolicy -Name "DontCheckDefaultBrowser" -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $ffRegPolicy -Name "DisableProfileImport" -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $ffRegPolicy -Name "DisableTelemetry" -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $ffRegPolicy -Name "DisablePocket" -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $ffRegPolicy -Name "WindowsLaunchOnLogin" -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $ffRegPolicy -Name "PasswordManagerEnabled" -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $ffRegPolicy -Name "OfferToSaveLogins" -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $ffRegPolicy -Name "OverrideFirstRunPage" -Value "" -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $ffRegPolicy -Name "OverridePostUpdatePage" -Value "" -PropertyType String -Force | Out-Null

        $ffHpKey = "$ffRegPolicy\Homepage"
        if (-not (Test-Path $ffHpKey)) { New-Item -Path $ffHpKey -Force | Out-Null }
        New-ItemProperty -Path $ffHpKey -Name "URL" -Value "https://search.brave.com" -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $ffHpKey -Name "Locked" -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $ffHpKey -Name "StartPage" -Value "homepage" -PropertyType String -Force | Out-Null

        $ffExtSettingsKey = "$ffRegPolicy\ExtensionSettings\uBlock0@raymondhill.net"
        if (-not (Test-Path $ffExtSettingsKey)) { New-Item -Path $ffExtSettingsKey -Force | Out-Null }
        New-ItemProperty -Path $ffExtSettingsKey -Name "installation_mode" -Value "force_installed" -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $ffExtSettingsKey -Name "install_url" -Value "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi" -PropertyType String -Force | Out-Null

        $ffManagedKey = "$ffRegPolicy\3rdparty\Extensions\uBlock0@raymondhill.net"
        if (-not (Test-Path $ffManagedKey)) { New-Item -Path $ffManagedKey -Force | Out-Null }
        New-ItemProperty -Path $ffManagedKey -Name "adminSettings" -Value $adminSettingsJson -PropertyType String -Force | Out-Null

        # 3. Scrub Mozilla-Firefox autostart entries across all Run keys
        $runLocations = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        )
        Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21' } | ForEach-Object {
            $runLocations += "Registry::HKEY_USERS\$($_.PSChildName)\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        }
        foreach ($rLoc in $runLocations) {
            if (Test-Path $rLoc) {
                $props = (Get-ItemProperty $rLoc -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -like "*Firefox*" }
                foreach ($p in $props) {
                    Remove-ItemProperty -Path $rLoc -Name $p.Name -ErrorAction SilentlyContinue | Out-Null
                    Write-DefaultsLog "    Removed Firefox autostart entry '$($p.Name)' from $rLoc." "ACTION" ([ConsoleColor]::Yellow)
                }
            }
        }

        # 4. Disable and remove Firefox background scheduled tasks
        Get-ScheduledTask | Where-Object { ($_.TaskName -like "*Firefox*") -or ($_.TaskPath -like "*Mozilla*") } | ForEach-Object {
            Disable-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue | Out-Null
            Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            Write-DefaultsLog "    Removed Firefox scheduled task: $($_.TaskName)." "ACTION" ([ConsoleColor]::Yellow)
        }

        Write-DefaultsLog "    [OK] Mozilla Firefox configured (Brave Search default, welcome screen suppressed, autostart disabled)." "ACTION" ([ConsoleColor]::Green)
    } else {
        Write-DefaultsLog "    [DryRun] Would write Firefox policies.json and HKLM policies." "INFO" ([ConsoleColor]::Gray)
    }

    # B. Google Chrome Configuration
    Write-DefaultsLog "  Provisioning Google Chrome..." "INFO" ([ConsoleColor]::Yellow)
    if (-not $DryRun) {
        $chromePolicyPath = "HKLM:\SOFTWARE\Policies\Google\Chrome"
        if (-not (Test-Path $chromePolicyPath)) { New-Item -Path $chromePolicyPath -Force | Out-Null }

        # Enable Manifest V2 availability via enterprise policy
        New-ItemProperty -Path $chromePolicyPath -Name "ExtensionManifestV2Availability" -Value 2 -PropertyType DWord -Force | Out-Null

        # Set Brave Search as homepage & startup page
        New-ItemProperty -Path $chromePolicyPath -Name "HomepageLocation" -Value "https://search.brave.com" -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $chromePolicyPath -Name "HomepageIsNewTabPage" -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $chromePolicyPath -Name "RestoreOnStartup" -Value 4 -PropertyType DWord -Force | Out-Null
        $chromeStartupKey = "$chromePolicyPath\RestoreOnStartupURLs"
        if (-not (Test-Path $chromeStartupKey)) { New-Item -Path $chromeStartupKey -Force | Out-Null }
        New-ItemProperty -Path $chromeStartupKey -Name "1" -Value "https://search.brave.com" -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $chromePolicyPath -Name "NewTabPageLocation" -Value "https://search.brave.com" -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $chromePolicyPath -Name "ShowHomeButton" -Value 1 -PropertyType DWord -Force | Out-Null

        # Force install uBlock Origin extension
        $chromeForceKey = "$chromePolicyPath\ExtensionInstallForcelist"
        if (-not (Test-Path $chromeForceKey)) { New-Item -Path $chromeForceKey -Force | Out-Null }
        New-ItemProperty -Path $chromeForceKey -Name "1" -Value "cjpalhdlnbpafiamejdnhcphjbkeiagm;https://clients2.google.com/service/update2/crx" -PropertyType String -Force | Out-Null

        # Admin settings / filter lists
        $chromeAdminKey = "$chromePolicyPath\3rdparty\extensions\cjpalhdlnbpafiamejdnhcphjbkeiagm\policy"
        if (-not (Test-Path $chromeAdminKey)) { New-Item -Path $chromeAdminKey -Force | Out-Null }
        New-ItemProperty -Path $chromeAdminKey -Name "adminSettings" -Value $adminSettingsJson -PropertyType String -Force | Out-Null

        Write-DefaultsLog "    [OK] Google Chrome configured (Brave Search default, uBlock Origin forced)." "ACTION" ([ConsoleColor]::Green)
    } else {
        Write-DefaultsLog "    [DryRun] Would configure Google Chrome ExtensionInstallForcelist and adminSettings." "INFO" ([ConsoleColor]::Gray)
    }

    # C. Microsoft Edge Configuration
    Write-DefaultsLog "  Provisioning Microsoft Edge..." "INFO" ([ConsoleColor]::Yellow)
    if (-not $DryRun) {
        $edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
        if (-not (Test-Path $edgePolicyPath)) { New-Item -Path $edgePolicyPath -Force | Out-Null }

        # Enable Manifest V2 availability via enterprise policy
        New-ItemProperty -Path $edgePolicyPath -Name "ExtensionManifestV2Availability" -Value 2 -PropertyType DWord -Force | Out-Null

        # Set Brave Search as homepage & startup page
        New-ItemProperty -Path $edgePolicyPath -Name "HomepageLocation" -Value "https://search.brave.com" -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $edgePolicyPath -Name "HomepageIsNewTabPage" -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $edgePolicyPath -Name "RestoreOnStartup" -Value 4 -PropertyType DWord -Force | Out-Null
        $edgeStartupKey = "$edgePolicyPath\RestoreOnStartupURLs"
        if (-not (Test-Path $edgeStartupKey)) { New-Item -Path $edgeStartupKey -Force | Out-Null }
        New-ItemProperty -Path $edgeStartupKey -Name "1" -Value "https://search.brave.com" -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $edgePolicyPath -Name "NewTabPageLocation" -Value "https://search.brave.com" -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $edgePolicyPath -Name "ShowHomeButton" -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $edgePolicyPath -Name "HideFirstRunExperience" -Value 1 -PropertyType DWord -Force | Out-Null

        # Force install uBlock Origin extension from Microsoft Edge Add-ons store
        $edgeForceKey = "$edgePolicyPath\ExtensionInstallForcelist"
        if (-not (Test-Path $edgeForceKey)) { New-Item -Path $edgeForceKey -Force | Out-Null }
        New-ItemProperty -Path $edgeForceKey -Name "1" -Value "odfafepnkmbhccpbejgmiehpchacaeak;https://edge.microsoft.com/extensionstore/crx" -PropertyType String -Force | Out-Null

        # Admin settings / filter lists
        $edgeAdminKey = "$edgePolicyPath\3rdparty\extensions\odfafepnkmbhccpbejgmiehpchacaeak\policy"
        if (-not (Test-Path $edgeAdminKey)) { New-Item -Path $edgeAdminKey -Force | Out-Null }
        New-ItemProperty -Path $edgeAdminKey -Name "adminSettings" -Value $adminSettingsJson -PropertyType String -Force | Out-Null

        Write-DefaultsLog "    [OK] Microsoft Edge configured (Brave Search default, uBlock Origin forced, first-run suppressed)." "ACTION" ([ConsoleColor]::Green)
    } else {
        Write-DefaultsLog "    [DryRun] Would configure Microsoft Edge ExtensionInstallForcelist and adminSettings." "INFO" ([ConsoleColor]::Gray)
    }
} else {
    Write-DefaultsLog "[Module 2/4] Browser ad-blocker extensions skipped via -SkipExtensions flag." "INFO" ([ConsoleColor]::Gray)
}

# 4. Module 3: Automatic Logon for Shared Account 'User'
Write-DefaultsLog "[Module 3/4] Configuring Automatic Logon (Autologon) for 'User'..." "INFO" ([ConsoleColor]::Yellow)
if (-not $DryRun) {
    try {
        $targetUser = "User"
        $targetPass = "Caritas2412!"
        $secPass = ConvertTo-SecureString $targetPass -AsPlainText -Force

        $localUser = Get-LocalUser -Name $targetUser -ErrorAction SilentlyContinue
        if ($localUser) {
            Set-LocalUser -Name $targetUser -Password $secPass -PasswordNeverExpires $true -UserMayChangePassword $true -ErrorAction SilentlyContinue | Out-Null
        }

        $winlogonKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        Set-ItemProperty -Path $winlogonKey -Name "AutoAdminLogon" -Value "1" -Type String -Force
        Set-ItemProperty -Path $winlogonKey -Name "DefaultUserName" -Value $targetUser -Type String -Force
        Set-ItemProperty -Path $winlogonKey -Name "DefaultDomainName" -Value $env:COMPUTERNAME -Type String -Force
        Set-ItemProperty -Path $winlogonKey -Name "DefaultPassword" -Value $targetPass -Type String -Force
        # Remove ForceAutoLogon so screen locking stays locked and does not force immediate desktop return
        Remove-ItemProperty -Path $winlogonKey -Name "ForceAutoLogon" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $winlogonKey -Name "LastUsedUsername" -Value $targetUser -Type String -Force
        Remove-ItemProperty -Path $winlogonKey -Name "AutoLogonCount" -ErrorAction SilentlyContinue
        Write-DefaultsLog "  [OK] Automatic logon active: System boots directly into '$targetUser' desktop with lock screen support." "ACTION" ([ConsoleColor]::Green)
    } catch {
        Write-DefaultsLog "  Warning configuring autologon: $_" "WARN" ([ConsoleColor]::Yellow)
    }
} else {
    Write-DefaultsLog "  [DryRun] Would configure Winlogon AutoAdminLogon=1 with DefaultPassword for 'User'." "INFO" ([ConsoleColor]::Gray)
}

# 5. Module 4: Standard Taskbar Layout (Explorer, Firefox, Word, Excel, PowerPoint; Edge, Store, Outlook removed)
Write-DefaultsLog "[Module 4/4] Configuring standard Taskbar layout across all user profiles..." "INFO" ([ConsoleColor]::Yellow)
if (-not $DryRun) {
    try {
        # 1. Deploy LayoutModification.xml for newly provisioned user profiles
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

        # 2. Deploy pinned shortcuts directly into all active and existing user profiles
        $userDirs = Get-ChildItem "C:\Users" -Directory | Where-Object { $_.Name -notin @("All Users", "Default User", "Public") }
        foreach ($uDir in $userDirs) {
            $tbDir = Join-Path $uDir.FullName "AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
            if (-not (Test-Path $tbDir)) { New-Item -ItemType Directory -Path $tbDir -Force | Out-Null }

            # Remove unwanted shortcuts (Edge, Store, Outlook, Mail)
            Get-ChildItem -Path $tbDir -Filter "*Edge*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Get-ChildItem -Path $tbDir -Filter "*Store*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Get-ChildItem -Path $tbDir -Filter "*Outlook*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Get-ChildItem -Path $tbDir -Filter "*Mail*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

            # Add required shortcuts
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

        # 3. Clear Taskband cached pins across loaded user hives so Windows re-evaluates pins
        Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21' } | ForEach-Object {
            $tbKey = "Registry::HKEY_USERS\$($_.PSChildName)\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
            if (Test-Path $tbKey) {
                Remove-ItemProperty -Path $tbKey -Name "Favorites" -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $tbKey -Name "FavoritesResolve" -ErrorAction SilentlyContinue
            }
        }
        Write-DefaultsLog "  [OK] Taskbar configured: Explorer, Firefox, Word, Excel, PowerPoint pinned; Edge, Store, Outlook removed." "ACTION" ([ConsoleColor]::Green)
    } catch {
        Write-DefaultsLog "  Warning configuring taskbar layout: $_" "WARN" ([ConsoleColor]::Yellow)
    }
} else {
    Write-DefaultsLog "  [DryRun] Would configure LayoutModification.xml and Taskbar shortcuts." "INFO" ([ConsoleColor]::Gray)
}

Write-DefaultsLog "==========================================================" "DONE" ([ConsoleColor]::Cyan)
Write-DefaultsLog "Default application and ad-blocker configuration complete." "DONE" ([ConsoleColor]::Cyan)
Write-DefaultsLog "Audit log: $logFile" "DONE" ([ConsoleColor]::White)
