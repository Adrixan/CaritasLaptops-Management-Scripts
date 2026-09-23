# CaritasLaptops-Management-Scripts

Everything necessary to keep the freely available Caritas laptops up to speed.

## Repository Structure

```
├── README.md
├── software-inventory.md          # User retention policy checklist ([x] keep / [ ] remove)
├── software-inventory-current.md  # Post-synchronization verified inventory
├── scripts/
│   ├── Configure-CaritasDefaults.ps1 # Machine-wide default app associations and ad-blocker policies
│   ├── Configure-CaritasHardening.ps1 # Standalone system hardening and power baseline policy
│   ├── Configure-CaritasMaintenanceAndPrivacy.ps1 # Credential defense, USB lockdown, and maintenance
│   ├── generate_inventory.py      # Queries WSMan registry and AppX manifests to rebuild inventory
│   ├── Reset-CaritasUserProfile.ps1 # Automated clean slate profile purge and isolation enforcement
│   ├── Sync-CaritasSoftware.ps1   # Core policy enforcement, winget update, and Windows Update script
│   └── test_winrm_connection.py   # Linux-side WinRM connectivity and privilege check
└── setup/
    ├── Enable-WinRMDev.ps1        # Enables WinRM and configures development access on target laptop
    └── Disable-WinRMDev.ps1       # Restores security baselines and disables WinRM when done
```

## Software Synchronization & Update Automation

The script [`scripts/Sync-CaritasSoftware.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Sync-CaritasSoftware.ps1) enforces the defined retention policy, updates all installed desktop and store applications, and synchronizes Windows Update (including hardware drivers and optional updates).

### Synchronization Phases

- **Phase 1:** Locates, verifies, and updates the Windows Package Manager (`winget`) and its source catalogs.
- **Phase 2:** Silently purges unselected Win32 desktop applications and deprovisions modern AppX bloatware packages ("Not more").
- **Phase 3:** Verifies that all required applications are present, automatically installing any missing tools via machine-scope winget ("Not fewer").
- **Phase 4:** Triggers automated package upgrades via `winget upgrade --all` and checks Microsoft Office LTSC Click-to-Run updates.
- **Phase 5:** Queries Windows Update online (`Microsoft.Update.Session`) for all pending updates, downloads them, and silently installs them. This includes:
  - Quality, security, and cumulative updates.
  - Hardware device drivers (Intel chipset, networking, audio, graphics, LPC controllers).
  - OEM system firmware and BIOS updates (e.g. Lenovo Ltd. Firmware).
  - All optional and preview updates.

### Running Locally on the Laptop (as `carit` with Admin Rights)

Log into `Caritas-X1-1` with user `carit`, open an elevated PowerShell prompt (**Run as Administrator**), and execute:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
C:\Caritas\Scripts\Sync-CaritasSoftware.ps1
```

Optional execution parameters:
- `-SkipWindowsUpdate`: Skips Windows Update and driver installation (runs only winget and retention tasks).
- `-SkipUpgrade`: Skips winget application upgrades (runs only retention and missing app installation).
- `-DryRun`: Scans and previews all removal, installation, winget upgrade, and Windows Update driver actions without altering the system.

Audit logs are continuously written with timestamps to:
```
C:\Caritas\Logs\SoftwareSync.log
```

---

## System Hardening & Operational Baseline Configuration

The script [`scripts/Configure-CaritasHardening.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Configure-CaritasHardening.ps1) establishes an operational baseline designed for shared public or community workstations. It enforces defensive security controls while keeping devices responsive and avoiding operational disruption.

### Hardening Modules
- **Module 1 (Continuous Power & Availability):** Disables standby sleep (`standby-timeout = 0`), system hibernation (`hibernate-timeout = 0`), and disk spindown (`disk-timeout = 0`) across both AC and DC profiles. Configures display blanking to 30 minutes (AC) and 15 minutes (DC). Completely disables hibernation via `powercfg /hibernate off` to purge `hiberfil.sys` and reclaim local storage. Sets AC lid close action to do nothing to maintain network accessibility.
- **Module 2 (Windows Defender Threat Mitigation):** Activates Potentially Unwanted Application (PUA) blocking against bundled adware and toolbars. Enforces real-time protection, behavioral monitoring, script scanning, IOAV file scanning, Advanced MAPS cloud reporting, and network protection against malicious domains.
- **Module 3 (Legacy Protocol & Peripheral Hardening):** Neutralizes USB AutoRun/AutoPlay (`NoDriveTypeAutoRun = 255`, `NoAutorun = 1`) to eliminate thumb drive malware vectors. Disables the legacy SMBv1 protocol feature. Disables Link-Local Multicast Name Resolution (LLMNR) via `EnableMulticast = 0` and disables NetBIOS over TCP/IP across all active network adapters to prevent local broadcast poisoning and credential harvesting.
- **Module 4 (Privacy & Telemetry Reduction):** Restricts diagnostic data telemetry to the minimum Required/Security baseline (`AllowTelemetry = 1`). Disables the advertising ID, suppresses Bing web search integration in the Start Menu, disables Activity Feed timeline history, and suppresses consumer promotional cloud app suggestions.
- **Module 5 (Safe Baseline Defaults for All Users):** Enforces visibility of registered file extensions by default (`HideFileExt DefaultValue = 0`) to prevent disguise of malicious executables. Disables Fast Startup (Hybrid Boot via `HiberbootEnabled = 0`) to prevent kernel session corruption and ensure clean reboots. Disables unsolicited Remote Assistance offers.

### Running Locally on the Laptop (as Administrator)

Open an elevated PowerShell prompt (**Run as Administrator**) and execute:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
C:\Caritas\Scripts\Configure-CaritasHardening.ps1
```

Execution switches:
- `-DryRun`: Previews all proposed registry, power, and policy adjustments without making system modifications.
- `-RevertToDefaults`: Reverts configured policies back to default Windows consumer settings.
- `-SkipPower`: Skips power and timeout adjustments.
- `-SkipDefender`: Skips Windows Defender preference configuration.
- `-SkipNetwork`: Skips protocol deprecation (SMBv1, LLMNR, NetBIOS, AutoRun).
- `-SkipPrivacy`: Skips telemetry, Start Menu search, and privacy modifications.

Audit logs are continuously recorded to:
```
C:\Caritas\Logs\Hardening.log
```

---

## Shared User Profile Reset & Clean Slate Automation

The script [`scripts/Reset-CaritasUserProfile.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Reset-CaritasUserProfile.ps1) manages the shared standard account `User` across all editions of Windows 11 (Home, Pro, Enterprise). It guarantees a clean slate whenever the human user changes and enforces decoupling from cloud identities.

### Core Architecture & Capabilities
- **WMI/CIM Profile Disposal (`Win32_UserProfile.Delete()`):** Terminates active or disconnected user sessions, halts background tasks, and unregisters the profile from `ProfileList`. The next logon clones a fresh template from `C:\Users\Default`, obliterating all downloads, browser cookies, cache, and saved credentials.
- **One-Click Public Desktop Shortcut:** Deploys a shortcut (`Sitzung zurücksetzen.lnk`) to `C:\Users\Public\Desktop`. Standard users or facilitators can double-click this shortcut without administrative privileges to trigger a complete session wipe.
- **Elevated Task Delegation:** Uses Windows Task Scheduler (`Caritas-ResetUserSession`) running under `NT AUTHORITY\SYSTEM` with highest privileges to perform the profile reset.
- **Boot-Time Automated Clean Slate:** Optionally configures `Caritas-ResetUserOnBoot` to purge and reset the profile on every system startup, ensuring no lingering session data persists overnight.
- **OneDrive & Microsoft Account Isolation:** Enforces machine-wide policies:
  - `NoConnectedUser = 3`: Blocks users from adding or linking Microsoft Accounts to their Windows profile.
  - `DisableFileSyncNGSC = 1` and `DisableFileSync = 1`: Disables OneDrive storage, prevents background synchronization, and suppresses OneDrive autostart.
  - `DisableSettingSync = 2`: Prevents cloud synchronization of Windows settings, themes, and passwords.
- **Account Privilege Enforcement:** Ensures `User` exists in the local SAM database with a non-expiring password, assigned strictly to the standard `Users` group (SID `S-1-5-32-545`) with zero administrative rights.

### Running Locally on the Laptop (as Administrator)

To provision the scheduled tasks, deploy the desktop shortcut, and apply isolation policies:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
C:\Caritas\Scripts\Reset-CaritasUserProfile.ps1 -InstallAll
```

Execution switches:
- `-InstallAll`: Convenience switch registering the SYSTEM scheduled task, the public desktop shortcut, and the boot-time task.
- `-RegisterTask`: Registers only the on-demand scheduled task `Caritas-ResetUserSession`.
- `-CreateDesktopShortcut`: Creates only the public desktop shortcut `Sitzung zurücksetzen.lnk`.
- `-RegisterBootTask`: Registers only the startup task `Caritas-ResetUserOnBoot`.
- `-TargetUsername <name>`: Specifies the target account (defaults to `User`).
- `-RebootAfterReset`: Restarts the operating system automatically after profile deletion.
- `-DryRun`: Previews actions without terminating sessions, deleting directories, or altering policies.

Audit logs are continuously written to:
```
C:\Caritas\Logs\UserReset.log
```

---

## Default Application Associations & Ad-Blocker Automation

The script [`scripts/Configure-CaritasDefaults.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Configure-CaritasDefaults.ps1) establishes machine-wide software defaults and privacy protection across all Windows 11 editions. It compiles an OEM default associations catalog, registers it via Group Policy, imports it into the Windows image via DISM, and provisions uBlock Origin enterprise policies across all browsers.

### Core Architecture & Capabilities
- **Web Protocols & PDF Viewing:** Enforces Mozilla Firefox as default for `http`, `https`, `.html`, `.htm`, `.shtml`, `.xhtml`, and `.pdf`. Uses Firefox's isolated, sandboxed viewer to eliminate Edge cloud sign-in prompts.
- **Media Playback:** Enforces VLC Media Player for all audio (`.mp3`, `.wav`, `.flac`, `.aac`, `.ogg`, `.m4a`, etc.), video (`.mp4`, `.mkv`, `.avi`, `.mov`, `.wmv`, `.flv`, `.webm`, etc.), and playlist (`.m3u`, `.pls`) formats.
- **Document Handlers:** Maps proprietary Microsoft Office formats (`.docx`, `.xlsx`, `.pptx`, `.doc`, `.xls`, `.ppt`) to Microsoft Office, and OpenDocument formats (`.odt`, `.ods`, `.odp`, `.odg`, `.odf`) to LibreOffice.
- **Archive Handlers:** Associates specialized compressed formats (`.7z`, `.rar`, `.tar`, `.gz`, `.bz2`, `.xz`, `.iso`) with 7-Zip, leaving standard `.zip` with Windows Explorer for ordinary patron navigation.
- **OEM Catalog & Image Policy:** Generates `C:\Caritas\Config\AppAssociations.xml`, registers the machine policy `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` -> `DefaultAssociationsConfiguration`, and imports associations via `dism /Online /Import-DefaultAppAssociations`. Both existing sessions and newly generated profiles (such as `User`) automatically inherit these mappings.
- **Multi-Browser Ad-Blocker Deployment:** Force-installs uBlock Origin across Mozilla Firefox, Google Chrome, and Microsoft Edge:
  - Mozilla Firefox: Configured via `distribution/policies.json` and registry `ExtensionSettings` (`uBlock0@raymondhill.net`).
  - Google Chrome & Microsoft Edge: Configured via `ExtensionInstallForcelist` with `ExtensionManifestV2Availability = 2` to preserve full webRequest filtering.
  - Managed Filter Lists: Pre-configures EasyList, EasyPrivacy, Malware protection (URLhaus), EasyList Germany (`DEU-0`) for Austrian/German regional domains, and EasyList Cookie / uBlock Annoyances to automatically suppress intrusive GDPR cookie banners.

### Running Locally on the Laptop (as Administrator)

Open an elevated PowerShell prompt (**Run as Administrator**) and execute:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
C:\Caritas\Scripts\Configure-CaritasDefaults.ps1
```

Execution switches:
- `-DryRun`: Previews all proposed association mappings and browser policies without making system modifications.
- `-SkipAssociations`: Skips file and protocol default application associations (runs only browser ad-blocker configuration).
- `-SkipExtensions`: Skips browser ad-blocker extension policies (runs only file and protocol association tasks).

Audit logs are continuously written to:
```
C:\Caritas\Logs\Defaults.log
```

---

## Maintenance, Browser Privacy & USB Lockdown Automation

The script [`scripts/Configure-CaritasMaintenanceAndPrivacy.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Configure-CaritasMaintenanceAndPrivacy.ps1) establishes essential privacy protections, USB removable media restrictions, desktop cleanliness, and automated storage maintenance.

### Core Modules
- **Module 1 (Browser Credential & Privacy Defense):** Eliminates patron credential leakage across Mozilla Firefox, Google Chrome, and Microsoft Edge by disabling password saving (`PasswordManagerEnabled = 0`, `OfferToSaveLogins = 0`), payment card autofill, and physical address caching. Suppresses commercial news feeds, promotional widgets, and telemetry, configuring a clean DuckDuckGo search homepage.
- **Module 2 (Removable Storage Execution Denial):** Enforces `Deny_Execute = 1` on the Removable Storage Devices class (`{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}`). Blocks execution of `.exe`, `.scr`, `.bat`, or scripts directly from USB thumb drives while retaining 100% read/write access for documents, PDFs, pictures, and media files.
- **Module 3 (Public Desktop Hygiene):** Scans `C:\Users\Public\Desktop` and purges orphaned `.lnk` shortcuts whose target binaries have been uninstalled, ensuring an uncluttered workspace for patrons.
- **Module 4 (Automated Storage Sense & Component Cleanup):** Enables Windows Storage Sense machine-wide to maintain free SSD space. Registers an automated monthly scheduled task (`Caritas-MonthlyMaintenance`) running under `NT AUTHORITY\SYSTEM` to execute DISM Component Store cleanup (`dism /StartComponentCleanup`) and purge old temporary files.

### Running Locally on the Laptop (as Administrator)

Open an elevated PowerShell prompt (**Run as Administrator**) and execute:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
C:\Caritas\Scripts\Configure-CaritasMaintenanceAndPrivacy.ps1
```

Execution switches:
- `-DryRun`: Previews all proposed policy changes, dead shortcut removals, and maintenance tasks without making modifications.
- `-SkipBrowserPrivacy`: Skips browser password manager and autofill lockdown.
- `-SkipUsbLockdown`: Skips USB removable media execution restrictions.
- `-SkipDesktopHygiene`: Skips public desktop dead shortcut scanning and purging.
- `-SkipStorageMaintenance`: Skips Storage Sense policy and monthly maintenance task registration.

Audit logs are continuously written to:
```
C:\Caritas\Logs\MaintenancePrivacy.log
```

---

## Setup and Remote Access Workflow

### 1. Enable WinRM on Target Laptop

On the target laptop (`Caritas-X1-1`), open an elevated PowerShell prompt (Run as Administrator) and run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
.\setup\Enable-WinRMDev.ps1
```

By default, this script:
- Switches the active network connection profile to `Private`.
- Starts and configures the `WinRM` service for automatic startup.
- Verifies or creates the local administrator account `CaritasAdmin` (prompts securely for password if missing).
- Sets `LocalAccountTokenFilterPolicy = 1` to disable UAC remote administrative filtering.
- Enables WSMan Negotiate (NTLM) authentication.
- Configures Windows Defender Firewall to permit inbound TCP port 5985.

### 2. Verify Connectivity from Management Station

From this Linux workstation, test connectivity and token privileges using `pypsrp` via `uv`:

```bash
uv run --with pypsrp scripts/test_winrm_connection.py --host 10.106.81.35 --user CaritasAdmin
```

### 3. Decommission WinRM After Development

Once development and deployment of management scripts are complete, restore security baselines on the laptop:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force

# Disables WinRM, removes listeners, blocks firewall, disables CaritasAdmin:
.\setup\Disable-WinRMDev.ps1

# Or permanently delete the local CaritasAdmin account:
.\setup\Disable-WinRMDev.ps1 -DeleteAdminAccount
```
