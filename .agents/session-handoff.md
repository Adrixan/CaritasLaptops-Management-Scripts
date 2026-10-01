# Session Handoff: Caritas Laptop Management Environment

## 1. Conversational Trajectory & Task History
- The objective was to design and implement a complete, production-grade management and maintenance automation system for donated Windows 11 laptops distributed by Caritas.
- Initial inquiries established requirements for unlinked patron accounts ('User') with zero cloud access, privacy isolation, automated profile resets, default browser/application mappings (Firefox, VLC, Office, LibreOffice, 7-Zip), and network-level ad-blocking (uBlock Origin across all browsers).
- Operational hardening policies were established: continuous power availability (no sleep/hibernation/standby), Defender PUA blocking, SMB1/LLMNR/NetBIOS deprecation, browser credential saving suppression, and USB executable lockdown.
- Inactivity console lock was explicitly rejected by user decision and excluded from all configurations.
- The user requested accessibility for non-technical administrative staff: both a Terminal User Interface (TUI) and a Graphical User Interface (GUI), zero-friction desktop launchers requiring no manual PowerShell commands or execution policy changes, automated 1-click onboarding for new laptops, an in-place self-updater checking GitHub with fast-fail offline timeouts, and an automated GitHub Actions release workflow.
- Subsequent refinement: Explicit rejection of deploying files to direct subfolders of `C:\` (such as `C:\Caritas`). The system was refactored so that deployment is completely portable and location-independent (e.g. directly on the administrative user's desktop `Desktop\CaritasScripts`), with root launchers (`Caritas-Verwaltung.cmd`, `Caritas-Verwaltung-TUI.cmd`), dynamic path resolution via `$PSScriptRoot`, and documentation in `README.md` updated to describe downloading directly from GitHub Releases without referencing WinRM development tooling.
- Profile reset refinement: Ensure profile reset of standard account `User` is strictly triggered either by `User` clicking a desktop shortcut or by the administrative user triggering the reset. Do not wipe the profile on each logout, shutdown, or system startup.
- Administrative login, Firefox onboarding, and desktop shortcut refinement:
  - Suppressed OOBE privacy setup questions (`DisablePrivacyExperience = 1`) and configured strict privacy defaults across machine and user hives.
  - Pre-configured Firefox with locked enterprise policies to eliminate `about:welcome` and default browser checks, and scrubbed `Run` registry keys to prevent autostart on logon.
  - Repaired desktop shortcut execution by refactoring batch invocation to pass PowerShell array arguments `@('-Sta', '-NoProfile', ...)`, targeting active administrator desktops.
- Character Encoding & Umlaut Resolution:
  - User reported character encoding issues regarding German umlauts inside the GUI of Caritas Verwaltung.
  - Root cause was Windows PowerShell 5.1 interpreting UTF-8 `.ps1` files lacking a Byte Order Mark (BOM) as ANSI (Windows-1252), causing multibyte German umlauts (`ä, ö, ü, Ä, Ö, Ü, ß`) and Unicode symbols (`⚡, ★, •, ▶, ✕`) to be read as mojibake.
  - Prepended standard UTF-8 BOM to all `.ps1` files and synchronized stream encoding.
- GUI Asynchronous Process Runner Deadlock Resolution:
  - Replaced synchronous stream reading with file-redirected process execution and shared reading (`FileShare.ReadWrite`), eliminating pipe handle deadlocks.
- Major UI & Execution Architecture Redesign (v1.0.6):
  - Implemented automatic Windows logon (Autologon) for standard account 'User' across setup, defaults, and profile reset scripts.
  - Rebranded GUI styling to authentic Caritas Corporate Identity (Caritas Red #C41230, accessible white/light gray surfaces, high contrast).
  - Replaced raw terminal shell view with a dedicated Progress & Status Dashboard.
  - Scalable layout with minimum boundary constraints (960x620) and dedicated exit button.
  - Fixed in-place update version comparison to strictly check if remote version is newer via System.Version.
  - Enhanced script verbosity with numbered execution stages.
- Patron Password Synchronization & Discord Eradication (v1.0.7):
  - Addressed password mismatch on reset: synchronized local SAM account password to 'Caritas2412!' and updated Winlogon DefaultPassword across all scripts.
  - Eradicated Discord and Discord System Helper (machine-wide Squirrel installers and autostart Run hooks).
- Browser Search Engine, Taskbar Layout, Screen Lock & Firefox Suppression (v1.0.8):
  - Brave Search Engine Default: Set home page, startup page, and new tab page to `https://search.brave.com` across Mozilla Firefox, Google Chrome, and Microsoft Edge via enterprise policies.
  - Standard Taskbar Layout: Configured `LayoutModification.xml` with `PinListPlacement="Replace"` to pin File Explorer, Firefox, Word, Excel, and PowerPoint for all users, while purging Microsoft Edge, Microsoft Store, and Outlook pins.
  - Workstation Screen Locking: Resolved issue where locking the workstation (`Win+L`) returned immediately to the desktop. Identified root cause as `ForceAutoLogon = 1` in Winlogon. Removed `ForceAutoLogon` across all scripts while preserving `AutoAdminLogon = 1` for boot auto-login.
  - Firefox First-Run & Terms of Use Suppression: Configured `SkipTermsOfUse = true`, `DisableFirefoxScreens = true`, `OverrideFirstRunPage = ""`, and autoconfig `firefox.cfg` locking `trailhead.firstrun.branches: nofirstrun-empty`.
  - Firefox Autostart Lockdown: Configured `WindowsLaunchOnLogin: false`, scrubbed `Mozilla-Firefox*` Run entries across all user and machine hives, and removed background scheduled tasks.
- Fleet Modernization, Handbook & End-to-End Automation (v1.0.9):
  - Inspected legacy setup instructions from `reference/` (`Handbuch.pdf` and `Handbuch.odt`).
  - Guaranteed `reference/` is ignored by version control in `.gitignore`.
  - Authored comprehensive modern manual `HANDBUCH.md` detailing hardware serial table, credentials, BIOS hotkeys, clean OS installation, 1-click suite onboarding, Office activation, TeamViewer, session resets, and in-place updates.
  - Implemented Candidate 1 (Automated BIOS Hostname Mapping): Hardware serial number lookup (`Win32_BIOS.SerialNumber`) mapped to laptop hostnames (`Caritas-T480-1`, `Caritas-X1-1`, `Caritas-Acer-1..4`, `Caritas-HP-1..2`) with automatic renaming via `Rename-Computer` in `setup/Install-CaritasEnvironment.ps1` and `scripts/Configure-CaritasHardening.ps1`.
  - Implemented Candidate 2 (Microsoft Office Silent Activation): Automated detection via `ospp.vbs` and activation using MAK key `[MANUELL-ZU-HINTERLEGEN]` in `setup/Install-CaritasEnvironment.ps1`, `scripts/Sync-CaritasSoftware.ps1`, and `scripts/Configure-CaritasDefaults.ps1`.
  - Implemented Candidate 3 (TeamViewer Unattended Remote Support): Pre-configured registry keys `Security_WinLogin = 2` (Windows authentication for all users) and `Always_Online = 1` with automatic service startup in `setup/Install-CaritasEnvironment.ps1`, `scripts/Sync-CaritasSoftware.ps1`, and `scripts/Configure-CaritasHardening.ps1`.
  - Implemented Candidate 4 (Zero-Touch USB Response File): Created `setup/autounattend.xml` bypassing Windows 11 hardware checks (TPM, CPU, RAM), formatting UEFI/GPT disks, setting `de-AT` locale, creating `CaritasAdmin`, bypassing OOBE privacy screens, and automatically launching into the administrator desktop.
  - Authored Publication-Quality PDF Edition (`HANDBUCH.pdf`):
    - Built a standalone, publication-grade A4 PDF manual in authentic Caritas Corporate Identity (Caritas Red #C41230, Inter / Liberation Sans, DejaVu Sans Mono, custom table column widths, and header/footer with page counters).
    - Deployed `setup/build-pdf.py` for reproducible compilation via Typst.
    - Updated release packaging workflow `.github/workflows/release.yml` to bundle and attach `HANDBUCH.pdf`.
    - Deployed `HANDBUCH.pdf` directly to test machine `CARITAS-X1-1` and uploaded asset to GitHub release `v1.0.9`.

- Administrative Account Protection & Emergency Recovery:
  - User reported losing administrative access on a computer after running the onboarding routine.
  - Root Cause Analysis:
    - Microsoft Account Policy Lockout: `Configure-CaritasHardening.ps1` sets `NoConnectedUser = 3`, disabling sign-in and elevation for Microsoft accounts (`caritas-laptops@outlook.com`).
    - Autologon Loop: `Reset-CaritasUserProfile.ps1` configures Winlogon `AutoAdminLogon = 1` for standard account `User` (`Caritas2412!`), auto-logging into the standard account on every reboot.
    - Account Demotion: If Windows was manually installed under an account named `User` with administrative rights, `Reset-CaritasUserProfile.ps1` demoted `User` from the local Administrators group without ensuring an alternative local administrator was provisioned.
  - Implemented Standalone Module `scripts/Ensure-CaritasAdminAccounts.ps1`:
    - Dynamically resolves the localized Administrators group via SID `S-1-5-32-544`.
    - Creates and enables `CaritasAdmin` with standard password `CariUntertasse-STMK-2025!`, `PasswordNeverExpires = $true`, and adds it to the local Administrators group.
    - Activates the built-in Windows `Administrator` account (SID ending in `-500`), sets the identical password, and ensures group membership.
    - Comprehensive file-based logging to `logs\AdminAccounts.log`.
  - Integrated into Master Onboarding & User Reset:
    - Updated `scripts/Caritas-ControlCenter.ps1` `Invoke-MasterOnboarding`: Added Phase 1 (`Ensure-CaritasAdminAccounts.ps1`) as the initial step before any software installation, hardening, or profile adjustments.
    - Updated `scripts/Caritas-ControlCenter.ps1` TUI menu: Added option `[7] Administrator-Konten sicherstellen (CaritasAdmin & Administrator)`.
    - Updated `scripts/Caritas-ControlCenter-GUI.ps1`: Added dedicated card `ADMINISTRATOR-ZUGANG ABSICHERN` with action button `btnEnsureAdmin` (`🛡 Administrator-Konten sicherstellen`), updated Hero description, and added asynchronous task execution handler with log redirection.
    - Updated `scripts/Reset-CaritasUserProfile.ps1`: Added pre-flight invocation of `Ensure-CaritasAdminAccounts.ps1` before modifying any administrative group memberships.
    - Updated `setup/Install-CaritasEnvironment.ps1`: Added step 6.8 provisioning `CaritasAdmin` and activating `Administrator` before configuring autologon.
  - Documented in Operational Manual:
    - Updated `HANDBUCH.md` Section 1 (credentials table with built-in Administrator), Section 4.3 (6 onboarding phases), Section 8 (logs table).
    - Authored Section 9: `Notfallwiederherstellung und Administrator-Zugriff` detailing the 3 technical root causes, automated prevention measures, 4 recovery procedures (Shift-Bypass, WinRE registry fix, WinRE utilman.exe swap, Safe Mode F4), and a concluding comparison table.
    - Recompiled publication-grade `HANDBUCH.pdf` via `setup/build-pdf.py` using Typst, achieving balanced 9-page layout without orphaned headings.
  - UTF-8 with BOM Enforcement:
    - Verified all `.ps1` script files are encoded as UTF-8 with BOM (`utf-8-sig`) to ensure full compatibility with Windows PowerShell 5.1 and eliminate mojibake.

## 2. Active Intent & Delivered Artifacts
All modules, launchers, and deployment artifacts are authored, validated, and verified:

- **Administrator Account Protection & Recovery Module:**
  - Files: [`scripts/Ensure-CaritasAdminAccounts.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Ensure-CaritasAdminAccounts.ps1), [`scripts/Deploy-CaritasAdminDesktop.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Deploy-CaritasAdminDesktop.ps1).
  - Standalone scripts provisioning `CaritasAdmin`, activating the built-in `Administrator` with password `CariUntertasse-STMK-2025!`, staging the suite in `C:\ProgramData\CaritasScripts`, and deploying `CaritasScripts` and launchers directly to `CaritasAdmin`'s desktop.

- **GUI and TUI Integration:**
  - Files: [`scripts/Caritas-ControlCenter-GUI.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Caritas-ControlCenter-GUI.ps1), [`scripts/Caritas-ControlCenter.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Caritas-ControlCenter.ps1).
  - Dedicated UI card and action button `btnEnsureAdmin` in GUI; Option `[7]` in TUI; Phase 1 in Onboarding.

- **Defensive Safeguards in Existing Pipelines:**
  - Files: [`scripts/Reset-CaritasUserProfile.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/scripts/Reset-CaritasUserProfile.ps1), [`setup/Install-CaritasEnvironment.ps1`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/setup/Install-CaritasEnvironment.ps1).
  - Pre-flight verification guaranteeing admin accounts exist before demoting or configuring autologon for `User`.

- **Handbook Documentation:**
  - Files: [`HANDBUCH.md`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/HANDBUCH.md), [`HANDBUCH.pdf`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/HANDBUCH.pdf), and [`setup/build-pdf.py`](file:///home/Adrixan/code/CaritasLaptops-Management-Scripts/setup/build-pdf.py).
  - Complete documentation of administrative credentials, 6-phase onboarding, and Section 9 emergency remediation procedures.

- **Zero-Touch USB Response File:**
  - File: `setup/autounattend.xml`.
  - Fully unattended Windows 11 Pro installation with LabConfig bypass for donated hardware, GPT partitioning, Austrian locale, and `CaritasAdmin` user provisioning.

- **Automated BIOS Hostname Assignment:**
  - Files: `setup/Install-CaritasEnvironment.ps1`, `scripts/Configure-CaritasHardening.ps1`.
  - Dynamic hardware query against pre-configured serial number lookup table; renames host automatically when serial matches.

- **Microsoft Office 2024 LTSC Silent Activation:**
  - Files: `setup/Install-CaritasEnvironment.ps1`, `scripts/Sync-CaritasSoftware.ps1`, `scripts/Configure-CaritasDefaults.ps1`.
  - Silent detection and activation via `cscript.exe //Nologo ospp.vbs /inpkey:...` and `/act`.

- **TeamViewer Unattended Support Baseline:**
  - Files: `setup/Install-CaritasEnvironment.ps1`, `scripts/Sync-CaritasSoftware.ps1`, `scripts/Configure-CaritasHardening.ps1`.
  - Pre-configures `Security_WinLogin = 2` (allowing remote login using `CaritasAdmin` credentials) and `Always_Online = 1`, and sets Windows service to Automatic.

## 3. Remote Verification & Hardware Testing
- Target Host: `10.106.81.35` (`CARITAS-X1-1`), Windows 11 Pro 64-bit Build 26100.
- Active Administrator: `CaritasAdmin`.
- Suite Location: `C:\Users\CaritasAdmin\Desktop\CaritasScripts\`.
- All verification assertions passed with 100% compliance:
  - `BIOS_SerialNumber`: `PF0YG5PW`
  - `OS_ComputerName`: `CARITAS-X1-1`
  - `Expected_Hostname`: `Caritas-X1-1` (Match: True)
  - `Office_OSPP_Path`: `C:\Program Files\Microsoft Office\Office16\ospp.vbs`
  - `Office_Is_Licensed`: True (`---LICENSED---`, MAK key ending `[KEY]`)
  - `TeamViewer_Service_Status`: Running (StartType: Automatic)
  - `TeamViewer_Security_WinLogin`: 2 (Windows Authentication for all users)
  - `TeamViewer_Always_Online`: 1
  - `Autounattend_Xml_Exists`: True (`8559` bytes)

## 4. Pending Decisions & Next Steps
- Review git diff and commit changes.
- Push updates to GitHub repository `Adrixan/CaritasLaptops-Management-Scripts`.
