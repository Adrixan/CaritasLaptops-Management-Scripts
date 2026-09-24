# CaritasLaptops-Management-Scripts

Complete management, hardening, and maintenance automation suite for community and patron laptops distributed by Caritas.

## Repository Structure

```
├── Caritas-Verwaltung.cmd             # Elevated 1-click launcher (Graphical Control Center)
├── Caritas-Verwaltung-TUI.cmd         # Elevated 1-click launcher (Terminal Control Center)
├── version.json                       # Version metadata & endpoints for self-updating
├── software-inventory.md              # User retention policy checklist ([x] keep / [ ] remove)
├── software-inventory-current.md      # Post-synchronization verified inventory
├── .github/
│   └── workflows/
│       └── release.yml                # Automated release bundle packaging & SHA256 generation
├── scripts/
│   ├── Caritas-ControlCenter-GUI.ps1  # Native WPF Graphical User Interface console
│   ├── Caritas-ControlCenter.ps1      # Interactive Terminal User Interface (TUI)
│   ├── Configure-CaritasDefaults.ps1  # Default app associations (Firefox, VLC, Office) & uBlock
│   ├── Configure-CaritasHardening.ps1 # Continuous power, Defender PUA, protocol deprecation
│   ├── Configure-CaritasMaintenanceAndPrivacy.ps1 # Password defense, USB execution denial
│   ├── Reset-CaritasUserProfile.ps1   # Automated clean slate profile purge & isolation
│   └── Sync-CaritasSoftware.ps1       # Package retention, winget updates, & Windows Update
└── setup/
    ├── Caritas-Verwaltung.cmd         # Subfolder mirror of GUI launcher
    ├── Caritas-Verwaltung-TUI.cmd     # Subfolder mirror of TUI launcher
    └── Install-CaritasEnvironment.ps1 # Optional desktop shortcut provisioner
```

---

## Quickstart Guide for Administrators & Facilitators

Deploying and maintaining a Caritas laptop requires zero command-line interaction and zero manual changes to PowerShell execution policies.

### 1. Download Latest Release
- On the target Windows 11 laptop, open any web browser and navigate to the GitHub Releases page:
  `https://github.com/Adrixan/CaritasLaptops-Management-Scripts/releases/latest`
- Download the distribution bundle `CaritasScripts.zip`.

### 2. Extract Archive
- Right-click `CaritasScripts.zip` and select **Extract All...**.
- Extract the contents onto the Administrative user's Desktop (for example, `Desktop\CaritasScripts`).

### 3. Launch the Management Console
- Open the extracted folder and double-click [`Caritas-Verwaltung.cmd`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/Caritas-Verwaltung.cmd).
- A standard Windows User Account Control (UAC) prompt will appear. Click **Yes**.
- The Graphical Control Center will launch immediately in high-contrast dark mode.
- If you prefer a keyboard-driven console, double-click [`Caritas-Verwaltung-TUI.cmd`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/Caritas-Verwaltung-TUI.cmd).

### 4. 1-Click Initial Onboarding (Fresh Devices)
- In the Control Center, click the green primary action button:
  `[▶ Erst-Einrichtung jetzt starten]`
- Confirm the dialog. The automated pipeline executes all five onboarding phases in sequence:
  - Phase 1: Software retention policy enforcement and missing tool installations via `winget`.
  - Phase 2: Complete Windows Update synchronization, driver installations, and firmware updates.
  - Phase 3: Defensive hardening, continuous power configuration (no sleep), and telemetry reduction.
  - Phase 4: Default application catalog registration (Firefox, VLC, Office) and uBlock Origin deployment.
  - Phase 5: Credential defense, USB execution denial, Storage Sense, and patron reset task registration.

### 5. Seamless In-Place Updates
- The Control Center checks GitHub for script updates upon loading.
- When an updated release is published, a notification button appears in the header (`⚡ Update auf vX.X.X installieren`).
- Clicking the button automatically downloads the updated scripts, extracts them into the current folder, and refreshes the version metadata without manual re-installation.

---

## Control Center Architecture (GUI & TUI)

### 1. Graphical User Interface (GUI)
The graphical console [`scripts/Caritas-ControlCenter-GUI.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Caritas-ControlCenter-GUI.ps1) is constructed using native Windows Presentation Framework (WPF) with XAML, requiring no third-party frameworks.
- Asynchronous Background Execution: Tasks run in decoupled PowerShell runspaces using thread-safe queues. The application interface remains fully responsive during heavy disk and network activity.
- Live Real-Time Console: Unified stdout and stderr streams render line-by-line into an auto-scrolling monospace terminal viewer.
- Immediate Task Interruption: An `[✕ Abbrechen]` button terminates active background runspaces cleanly if an operation was initiated by mistake.
- Action Cards:
  - **Erst-Einrichtung (All-in-One):** Complete automated onboarding for freshly donated laptops.
  - **Vollständige Wartung:** Full software sync, winget package upgrades, and Windows Update drivers.
  - **Schnelle Software-Wartung:** Winget upgrades and package retention only (skips Windows Update).
  - **Standard-Programme & Werbeblocker:** App catalog associations and multi-browser uBlock Origin policies.
  - **Sicherheits- & Energie-Richtlinien:** Defender PUA, continuous power baseline, and protocol deprecation.
  - **Datenschutz & USB-Sperre:** Browser password saving suppression, USB execution denial, storage hygiene.
  - **Benutzerkonto 'User' zurücksetzen:** Full clean slate CIM profile reset for the shared patron account.
  - **Utility Row:** Dedicated buttons to switch to Terminal (TUI) mode, open the local `logs\` directory, clear console output, and force manual update checks.

### 2. Terminal User Interface (TUI)
The terminal console [`scripts/Caritas-ControlCenter.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Caritas-ControlCenter.ps1) provides an interactive keyboard-driven menu:
- Numerical selection `[1]` through `[9]` and `[L]` triggers operations without multi-step prompts.
- Unattended execution support via `-RunOnboardingUnattended` for scripted execution.
- Built-in audit log reader displaying the last 40 lines of any log in the local `logs\` directory.
- Option `[8]` hands execution over to the graphical interface.

---

## Technical Module Specifications

### 1. Software Synchronization & Update Automation
The script [`scripts/Sync-CaritasSoftware.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Sync-CaritasSoftware.ps1) enforces software retention, upgrades desktop tools, and pulls Windows Updates:
- Phase 1: Locates, validates, and initializes the Windows Package Manager (`winget`).
- Phase 2: Silently purges unselected Win32 desktop applications and modern AppX bloatware.
- Phase 3: Verifies all approved core applications are present, installing missing packages via `winget`.
- Phase 4: Executes `winget upgrade --all` and triggers Microsoft Office Click-to-Run updates.
- Phase 5: Queries Windows Update online (`Microsoft.Update.Session`), downloading and installing cumulative security updates, OEM firmware, and device drivers (Intel, Realtek, Lenovo, HP, Dell).
- Logging: Recorded to `logs\SoftwareSync.log` relative to the script suite.

### 2. System Hardening & Operational Baseline
The script [`scripts/Configure-CaritasHardening.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Configure-CaritasHardening.ps1) enforces stability and security for shared workstations:
- Continuous Availability: Disables standby timeout, hibernation timeout, and disk spindown across AC/DC profiles. Disables hibernation via `powercfg /hibernate off` to purge `hiberfil.sys` and reclaim SSD space. Sets AC lid close action to do nothing.
- Windows Defender Threat Mitigation: Enables Potentially Unwanted Application (PUA) blocking, real-time protection, script scanning, IOAV archive scanning, and cloud protection.
- Peripheral & Protocol Hardening: Disables AutoRun/AutoPlay (`NoDriveTypeAutoRun = 255`) to eliminate thumb drive infection vectors. Disables legacy SMBv1, LLMNR multicast resolution, and NetBIOS over TCP/IP across all network adapters.
- Privacy & Telemetry: Restricts diagnostic data telemetry to the minimum Required baseline (`AllowTelemetry = 1`), disables advertising ID, and disables Start Menu web search integration.
- Baseline Defaults: Enforces visible file extensions (`HideFileExt = 0`) and disables Fast Startup (Hybrid Boot) to prevent kernel session corruption.
- Logging: Recorded to `logs\Hardening.log`.

### 3. Shared Patron Profile Reset & Clean Slate
The script [`scripts/Reset-CaritasUserProfile.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Reset-CaritasUserProfile.ps1) isolates and manages the shared patron account `User`:
- CIM Profile Disposal: Calls `Win32_UserProfile.Delete()` to terminate active patron sessions, unregister the profile from registry, and purge the user directory. The subsequent login clones a fresh template from `Default`.
- Unprivileged Patron Trigger: Deploys a shortcut (`Sitzung zurücksetzen.lnk`) to `C:\Users\Public\Desktop` allowing patrons or volunteers to initiate an immediate profile wipe without administrative credentials.
- SYSTEM Task Delegation: Executes via an elevated Windows Scheduled Task (`Caritas-ResetUserSession`) running under `NT AUTHORITY\SYSTEM` with explicit execute permissions granted to `Builtin\Users`.
- Strict On-Demand Execution: Resets are exclusively triggered on demand, either by clicking the desktop shortcut or through the administrator Control Center. Profiles are intentionally never purged automatically on reboot, shutdown, or logout to safeguard patron work across routine restarts.
- Cloud Identity Lockdown: Enforces `NoConnectedUser = 3` (blocks Microsoft Account linking), `DisableFileSyncNGSC = 1` (disables OneDrive storage and background sync), and `DisableSettingSync = 2` (prevents settings synchronization).
- Logging: Recorded to `logs\UserReset.log`.

### 4. Default Applications & Ad-Blocker Automation
The script [`scripts/Configure-CaritasDefaults.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Configure-CaritasDefaults.ps1) establishes system-wide associations and web filtering:
- Protocol & Extension Catalog: Compiles an OEM association catalog mapping Mozilla Firefox for web and PDF viewing, VLC Media Player for all audio/video formats, Microsoft Office for proprietary formats, LibreOffice for OpenDocument formats, and 7-Zip for compressed archives.
- Live DISM Import: Applies associations into the active system image via `dism.exe /Online /Import-DefaultAppAssociations` and enforces `DefaultAssociationsConfiguration` via Group Policy.
- Multi-Browser Ad-Blocker: Force-installs uBlock Origin across Mozilla Firefox, Google Chrome, and Microsoft Edge via enterprise policies.
- Curated Filter Lists: Pre-configures EasyList, EasyPrivacy, Malware protection (URLhaus), EasyList Germany (`DEU-0`) for regional websites, and EasyList Cookie / uBlock Annoyances to automatically suppress intrusive cookie consent banners.
- Logging: Recorded to `logs\Defaults.log`.

### 5. Maintenance, Browser Privacy & USB Lockdown
The script [`scripts/Configure-CaritasMaintenanceAndPrivacy.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Configure-CaritasMaintenanceAndPrivacy.ps1) provides ongoing hygiene:
- Browser Credential Defense: Disables password manager prompts, credit card autofill, and address caching across Firefox, Chrome, and Edge. Suppresses promotional news feeds and telemetry.
- Removable Media Execution Denial: Enforces `Deny_Execute = 1` on removable storage devices (`{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}`). Blocks `.exe`, `.bat`, and scripts from executing from USB thumb drives while retaining read/write access for documents and media.
- Public Desktop Hygiene: Purges dead or orphaned `.lnk` shortcuts whose target binaries were removed.
- Storage Sense & Maintenance Task: Activates Windows Storage Sense and registers an automated monthly task (`Caritas-MonthlyMaintenance`) running DISM component store cleanup (`dism /StartComponentCleanup`).
- Logging: Recorded to `logs\MaintenancePrivacy.log`.

---

## Automated GitHub Release Pipeline

The repository includes a continuous integration workflow in [`.github/workflows/release.yml`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/.github/workflows/release.yml):
- Trigger: Pushing a version tag matching `v*.*.*` initiates packaging.
- Distribution Archive: Compiles `CaritasScripts.zip`, containing top-level launchers, scripts, configuration, and documentation ready for immediate extraction.
- Cryptographic Verification: Computes a SHA256 checksum (`CaritasScripts.zip.sha256`) and attaches both files to the GitHub Release.

To publish a new version:
```bash
git tag v1.0.1
git push origin v1.0.1
```
Laptops running the Control Center will detect the new version within seconds and prompt administrators to update in place.
