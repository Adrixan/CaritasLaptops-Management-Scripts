# Session Handoff: Caritas Laptop Management Environment

## 1. Conversational Trajectory & Task History
- The objective was to design and implement a complete, production-grade management and maintenance automation system for donated Windows 11 laptops distributed by Caritas.
- Initial inquiries established requirements for unlinked patron accounts ('User') with zero cloud access, privacy isolation, automated profile resets, default browser/application mappings (Firefox, VLC, Office, LibreOffice, 7-Zip), and network-level ad-blocking (uBlock Origin across all browsers).
- Operational hardening policies were established: continuous power availability (no sleep/hibernation/standby), Defender PUA blocking, SMB1/LLMNR/NetBIOS deprecation, browser credential saving suppression, and USB executable lockdown.
- Inactivity console lock (Option 2) was explicitly rejected by user decision and excluded from all configurations.
- The user requested accessibility for non-technical administrative staff: both a Terminal User Interface (TUI) and a Graphical User Interface (GUI), zero-friction desktop launchers requiring no manual PowerShell commands or execution policy changes, automated 1-click onboarding for new laptops, an in-place self-updater checking GitHub with fast-fail offline timeouts, and an automated GitHub Actions release workflow.
- Subsequent refinement: Explicit rejection of deploying files to direct subfolders of `C:\` (such as `C:\Caritas`). The system was refactored so that deployment is completely portable and location-independent (e.g. directly on the administrative user's desktop `Desktop\CaritasScripts`), with root launchers (`Caritas-Verwaltung.cmd`, `Caritas-Verwaltung-TUI.cmd`), dynamic path resolution via `$PSScriptRoot`, and documentation in `README.md` updated to describe downloading directly from GitHub Releases without referencing WinRM development tooling.
- User Request 10 refinement: Ensure profile reset of standard account `User` is strictly triggered either by `User` clicking a desktop shortcut or by the administrative user triggering the reset. Do not wipe the profile on each logout, shutdown, or system startup.

## 2. Active Intent & Delivered Artifacts
All modules, launchers, and deployment artifacts are authored, validated, and verified on the target hardware (`CARITAS-X1-1`, Windows 11 Pro 64-bit):

1. **Strictly On-Demand Patron Profile Reset:**
   - Script: `scripts/Reset-CaritasUserProfile.ps1`
   - Unprivileged Execution Mechanism: Configured elevated Scheduled Task `Caritas-ResetUserSession` (running under `NT AUTHORITY\SYSTEM`). Task security descriptor updated via COM (`Schedule.Service`) granting `(A;;0x12019f;;;BU)` and filesystem ACLs granting `icacls *S-1-5-32-545:(RX)` on `C:\Windows\System32\Tasks\Caritas-ResetUserSession`.
   - Public Desktop Shortcut: Created `C:\Users\Public\Desktop\Sitzung zurücksetzen.lnk` pointing to `schtasks.exe /run /tn "Caritas-ResetUserSession"`, allowing standard patrons to trigger an immediate clean slate wipe without administrative credentials or UAC prompts.
   - Elimination of Boot/Shutdown/Logout Wipes: Parameter `-RegisterBootTask` and the scheduled task `Caritas-ResetUserOnBoot` were permanently decommissioned and actively unregistered. Profiles persist across reboots, logouts, and shutdowns.
   - SAM and Policy Integrity: Guarantees account `User` exists as a standard unprivileged local user, password never expires, with machine policies enforcing `NoConnectedUser = 3`, `DisableFileSyncNGSC = 1`, and `DisableSettingSync = 2`.

2. **Native Graphical User Interface (GUI):**
   - File: `scripts/Caritas-ControlCenter-GUI.ps1`
   - Framework: 100% native .NET Windows Presentation Framework (WPF) with zero external runtime dependencies.
   - Design: Tech-wear professional dark palette ("Bioluminescent Night": `#121212` background, `#1E1E1E` panels, `#4ADE80` Digital Fern primary accents, `#EF4444` danger reset accents).
   - Dynamic Paths: Resolves `$scriptDir`, `$configDir`, and `$logDir` relative to `$PSScriptRoot` without hardcoded drive paths.
   - Concurrency: Background runspaces with thread-safe `ConcurrentQueue` and `DispatcherTimer` polling every 50 ms.
   - Interactive Elements: Action cards for 1-Click Erst-Einrichtung, system maintenance, configuration, patron reset, live console box with auto-scrolling, process cancellation button, and fast-fail GitHub update badge.

3. **Interactive Terminal User Interface (TUI):**
   - File: `scripts/Caritas-ControlCenter.ps1`
   - Single-key navigation menu, unattended onboarding support (`-RunOnboardingUnattended`), audit log viewer for local `logs\`, fast-fail update checker (2.5 s timeout), and bidirectional handoff to GUI via option `[8]`.

4. **Zero-Friction Desktop Launchers:**
   - Files: `Caritas-Verwaltung.cmd`, `Caritas-Verwaltung-TUI.cmd` (at root and in `setup/`)
   - Dynamically resolves script paths relative to `%~dp0`. Executes PowerShell in Single-Thread Apartment mode with per-process execution policy bypass (`-ExecutionPolicy Bypass`), invoking elevated UAC prompts without requiring manual PowerShell interaction.
   - Desktop Shortcuts: `Caritas Verwaltung.lnk` and `Caritas Verwaltung (Terminal).lnk` point directly to the local folder on `C:\Users\carit\Desktop\CaritasScripts`.

5. **1-Step Desktop Environment Provisioner:**
   - File: `setup/Install-CaritasEnvironment.ps1`
   - Initializes local subdirectories (`config`, `logs`) in place without creating folders on `C:\`, excludes standard patron `User` from receiving administrative shortcuts, and provisions desktop launchers on administrative profiles.

6. **Documentation & User Guide:**
   - File: `README.md`
   - Clarified that profile resets are strictly on demand (via desktop shortcut or admin Control Center) and never automatic on reboot, shutdown, or logout. Version bumped to `1.0.2` in `version.json`.

## 3. Remote Verification & Hardware Testing
- Target Host: `10.106.81.35` (`CARITAS-X1-1`), Windows 11 Pro 64-bit Build 26100.
- Scheduled Tasks Verified:
  - `Caritas-MonthlyMaintenance`: Ready (monthly component cleanup).
  - `Caritas-ResetUserSession`: Ready (on-demand SYSTEM task with `BU` execute rights).
  - `Caritas-ResetUserOnBoot`: Verified absent / unregistered.
- Unprivileged Execution Test: Tested `schtasks.exe /run /tn "Caritas-ResetUserSession"` under impersonated authentic `Caritas-X1-1\User` token. Completed with ExitCode 0, successfully triggering profile disposal without UAC.
- Desktop Shortcuts: Verified `C:\Users\Public\Desktop\Sitzung zurücksetzen.lnk` exists and points to Task Scheduler reset task.
- Zero `C:\Caritas` Files: Confirmed `Test-Path C:\Caritas` returns `False`.
- WinRM left active and functional on target laptop per user instructions.

## 4. Pending Decisions & Next Steps
- Commit repository changes, bump tag to `v1.0.2`, and push to GitHub repository `Adrixan/CaritasLaptops-Management-Scripts` to trigger the automated release pipeline.
