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

## 2. Active Intent & Delivered Artifacts
All modules, launchers, and deployment artifacts are authored, validated, and verified on the target hardware (`CARITAS-X1-1`, Windows 11 Pro 64-bit):

- **Brave Search Engine Configuration:**
  - Firefox: Configured `Homepage.URL = "https://search.brave.com"`, `Locked = true`, `StartPage = "homepage"` in `distribution\policies.json`, `firefox.cfg`, and HKLM registry.
  - Google Chrome: Configured `HomepageLocation`, `RestoreOnStartup = 4`, `RestoreOnStartupURLs\1`, and `NewTabPageLocation` in `HKLM:\SOFTWARE\Policies\Google\Chrome`.
  - Microsoft Edge: Configured `HomepageLocation`, `RestoreOnStartup = 4`, `RestoreOnStartupURLs\1`, and `NewTabPageLocation` in `HKLM:\SOFTWARE\Policies\Microsoft\Edge`.
  - Scripts: `scripts/Configure-CaritasDefaults.ps1`, `scripts/Configure-CaritasMaintenanceAndPrivacy.ps1`.

- **Standard Taskbar Layout Customization:**
  - Deployed `C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml` utilizing `<CustomTaskbarLayoutCollection PinListPlacement="Replace">` with File Explorer, Firefox, Word, Excel, and PowerPoint.
  - Pinned shortcuts copied into `AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar` across all user profiles.
  - Purged Microsoft Edge, Microsoft Store, Outlook, and Mail shortcuts.
  - Cleared `Taskband\Favorites` and `FavoritesResolve` cache across all user registry hives.
  - Scripts: `scripts/Configure-CaritasDefaults.ps1`, `setup/Install-CaritasEnvironment.ps1`, `scripts/Reset-CaritasUserProfile.ps1`.

- **Workstation Lock Screen Restoration:**
  - Removed `ForceAutoLogon` from `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon`.
  - Preserved `AutoAdminLogon = "1"`, `DefaultUserName = "User"`, `DefaultPassword = "Caritas2412!"`.
  - Machine boots straight to desktop on startup, while manual workstation locking (`Win+L`) remains safely on the lock screen without returning to desktop.
  - Scripts: `scripts/Configure-CaritasDefaults.ps1`, `setup/Install-CaritasEnvironment.ps1`, `scripts/Reset-CaritasUserProfile.ps1`.

- **Firefox Welcome Screen & Terms of Use Elimination:**
  - Configured `SkipTermsOfUse: true`, `DisableFirefoxScreens: true`, `OverrideFirstRunPage: ""`, `OverridePostUpdatePage: ""` in `policies.json`.
  - Created machine-wide `defaults\pref\autoconfig.js` and `firefox.cfg` locking `trailhead.firstrun.branches: "nofirstrun-empty"`, `trailhead.firstrun.didSeeAboutWelcome: true`, and `browser.aboutwelcome.enabled: false`.
  - Mirrored `SkipTermsOfUse = 1`, `DisableFirefoxScreens = 1` in `HKLM:\SOFTWARE\Policies\Mozilla\Firefox`.
  - Scripts: `scripts/Configure-CaritasDefaults.ps1`, `scripts/Configure-CaritasMaintenanceAndPrivacy.ps1`.

- **Firefox Autostart Elimination:**
  - Configured `WindowsLaunchOnLogin = false` in `policies.json` and locked `browser.startup.windowsLaunchOnLogin.enabled: false` and `browser.startup.windowsLaunchOnLogin.disable: true` in `firefox.cfg`.
  - Scrubbed `Mozilla-Firefox*` Run keys across all user registry hives and HKLM.
  - Removed background scheduled tasks.
  - Scripts: `scripts/Configure-CaritasDefaults.ps1`, `scripts/Configure-CaritasMaintenanceAndPrivacy.ps1`, `scripts/Reset-CaritasUserProfile.ps1`.

## 3. Remote Verification & Hardware Testing
- Target Host: `10.106.81.35` (`CARITAS-X1-1`), Windows 11 Pro 64-bit Build 26100.
- Active Administrator: `CaritasAdmin`.
- Suite Location: `C:\Users\CaritasAdmin\Desktop\CaritasScripts\`.
- All verification assertions passed with 100% compliance:
  - `FF_Policies_Homepage_URL`: `https://search.brave.com` (Locked: True)
  - `Chrome_HomepageLocation` & `Edge_HomepageLocation`: `https://search.brave.com` (RestoreOnStartup: 4)
  - `Default_LayoutModification_Exists`: True (`PinListPlacement="Replace"`, Explorer, Firefox, Word, Excel, PowerPoint)
  - Taskbar Shortcuts: Edge, Store, Outlook confirmed absent across all user profiles; Explorer, Firefox, Office confirmed present
  - `Winlogon_ForceAutoLogon`: Empty ($null), `Winlogon_AutoAdminLogon`: 1, `DefaultPassword`: Caritas2412!
  - `FF_Cfg_AboutWelcome_Disabled`: True, `FF_Cfg_Trailhead_NoFirstRun`: True, `SkipTermsOfUse`: True
  - `Firefox_Run_Keys_Count`: 0, `Firefox_Scheduled_Tasks_Count`: 0
  - Live Reset Verification: Executed `Install-CaritasEnvironment.ps1` and `Reset-CaritasUserProfile.ps1` live. Validated account credentials via .NET PrincipalContext and verified lock settings persist without regressions.

## 4. Pending Decisions & Next Steps
- Commit repository changes, tag `v1.0.8`, and push to GitHub repository `Adrixan/CaritasLaptops-Management-Scripts` to trigger the automated release workflow.
- Monitor GitHub Actions release build.
