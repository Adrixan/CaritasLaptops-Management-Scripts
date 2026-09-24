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
  - When logging into Windows as an administrator, Windows presented initial OOBE setup questions (location, diagnostic data, tailored experiences, advertising ID, inking/typing, find my device). These questions must never appear and must default to strict privacy settings.
  - Firefox opened with an onboarding configuration dialogue (`about:welcome`) and autostarted on login. Firefox must be pre-configured, ready to use immediately without wizard dialogues, and must never start automatically on logon.
  - The desktop shortcut "Caritas Verwaltung" failed to launch due to cmd/powershell argument quoting breakdown and path misalignment with the disabled `carit` account.

## 2. Active Intent & Delivered Artifacts
All modules, launchers, and deployment artifacts are authored, validated, and verified on the target hardware (`CARITAS-X1-1`, Windows 11 Pro 64-bit):

1. **OOBE Privacy Setup Suppression & Privacy Defaults:**
   - Script: `scripts/Configure-CaritasHardening.ps1`
   - OOBE Suppression: Configured `DisablePrivacyExperience = 1` in `HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE`, `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`, and `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System`.
   - Animation & SCOOBE Bypass: Set `EnableFirstLogonAnimation = 0`, `ScoobeSystemSettingEnabled = 0`, `ShowWindowsProvider = 0`, and `RestartApps = 0` (preventing automatic reopening of apps on sign-in).
   - Strict Sensory & Input Privacy: Set `DisableLocation = 1`, `DisableLocationScripting = 1`, `DisableSensors = 1`, and forced `ConsentStore\location` to `Deny`. Restricted implicit inking and text collection (`AllowInputPersonalization = 0`, `RestrictImplicitInkCollection = 1`, `RestrictImplicitTextCollection = 1`).
   - Find My Device & Speech: Set `AllowFindMyDevice = 0` and `AllowSpeechModelUpdate = 0`.
   - Hive Stamping: Automatically stamped privacy acceptance flags and disabled Content Delivery Manager suggestions across `.DEFAULT` and all active user registry hives (`S-1-5-21*`).

2. **Firefox Enterprise Pre-Configuration & Autostart Suppression:**
   - Scripts: `scripts/Configure-CaritasDefaults.ps1`, `scripts/Configure-CaritasMaintenanceAndPrivacy.ps1`
   - Enterprise Policies: Deployed `C:\Program Files\Mozilla Firefox\distribution\policies.json` and mirrored HKLM registry policies locking `browser.aboutwelcome.enabled: false`, `trailhead.firstrun.didSeeAboutWelcome: true`, `doh-rollout.doneFirstRun: true`, `OverrideFirstRunPage: ""`, `OverridePostUpdatePage: ""`, `DontCheckDefaultBrowser: 1`, `DisableProfileImport: 1`, `DisablePocket: 1`, and `DisableTelemetry: 1`.
   - Autostart Lockdown: Locked `browser.startup.windowsLaunchOnLogin.enabled: false`. Scrubbed Firefox autostart entries from `Run` keys across HKLM, WOW6432Node, HKCU, and all mounted user hives (`S-1-5-21*`). Disabled Firefox background maintenance scheduled tasks.

3. **Desktop Shortcut Launcher & Quoting Fix:**
   - Files: `Caritas-Verwaltung.cmd`, `Caritas-Verwaltung-TUI.cmd` (at root and in `setup/`)
   - Fixed argument escaping by passing a native PowerShell array `@('-Sta', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '%TARGET_SCRIPT%')`, preventing argument truncation or empty-string parsing.
   - Updated provisioner `setup/Install-CaritasEnvironment.ps1` to detect active local administrator profiles dynamically and deploy shortcuts to `C:\Users\CaritasAdmin\Desktop`.

4. **PowerShell 5.1 Registry Parameter Compatibility:**
   - Standardized on `New-ItemProperty -PropertyType ... -Force` across all modules, replacing invalid `Set-ItemProperty -Type` calls that triggered parameter binding errors on native PowerShell 5.1.

5. **Strictly On-Demand Patron Profile Reset:**
   - Script: `scripts/Reset-CaritasUserProfile.ps1`
   - Unprivileged Execution Mechanism: Elevated Scheduled Task `Caritas-ResetUserSession` under `NT AUTHORITY\SYSTEM` with security descriptor `(A;;0x12019f;;;BU)` and file ACL `icacls *S-1-5-32-545:(RX)` on the task definition.
   - Public Desktop Shortcut: `C:\Users\Public\Desktop\Sitzung zurücksetzen.lnk` pointing to `schtasks.exe /run /tn "Caritas-ResetUserSession"`.
   - Profiles persist across routine reboots, logouts, and shutdowns.

6. **Native Control Centers (GUI & TUI):**
   - GUI: `scripts/Caritas-ControlCenter-GUI.ps1` (WPF/XAML, runspace concurrency, Bioluminescent Night palette, live terminal viewer).
   - TUI: `scripts/Caritas-ControlCenter.ps1` (single-key interaction, audit log viewer, unattended switch).
   - Version metadata bumped to `1.0.3` in `version.json`.

## 3. Remote Verification & Hardware Testing
- Target Host: `10.106.81.35` (`CARITAS-X1-1`), Windows 11 Pro 64-bit Build 26100.
- Active Administrator: `CaritasAdmin`.
- Suite Location: `C:\Users\CaritasAdmin\Desktop\CaritasScripts\`.
- Shortcuts Verified on `CaritasAdmin` Desktop:
  - `Caritas Verwaltung.lnk` -> `C:\Users\CaritasAdmin\Desktop\CaritasScripts\Caritas-Verwaltung.cmd` (Verified `Exists: True`).
  - `Caritas Verwaltung (Terminal).lnk` -> `C:\Users\CaritasAdmin\Desktop\CaritasScripts\Caritas-Verwaltung-TUI.cmd` (Verified `Exists: True`).
- Launcher Argument Parsing: Remote test of PowerShell array argument construction passed with 6 arguments and exit code 0.
- Scheduled Tasks Verified:
  - `Caritas-MonthlyMaintenance`: Ready.
  - `Caritas-ResetUserSession`: Ready (pointing to active admin desktop path, unprivileged trigger functional).
  - `Caritas-ResetUserOnBoot`: Decommissioned and absent.
- OOBE & Privacy Keys Verified:
  - `DisablePrivacyExperience = 1` in `HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE`.
  - `DisableLocation = 1`, `DisableLocationScripting = 1`, `DisableSensors = 1` in `HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors`.
  - Privacy consent and SCOOBE bypass stamped across user hives.
- Firefox Configuration Verified:
  - `C:\Program Files\Mozilla Firefox\distribution\policies.json` deployed with locked first-run bypass and autostart denial.
  - Autostart `Run` registry keys verified clean across all user hives.
- Network Management: WinRM port 5985 left active on `CARITAS-X1-1` per user instructions.

## 4. Pending Decisions & Next Steps
- Commit repository changes, tag `v1.0.3`, and push to GitHub repository `Adrixan/CaritasLaptops-Management-Scripts` to trigger the automated release workflow.
