# Session Handoff: Caritas Laptop Management Environment

## 1. Conversational Trajectory & Task History
- The objective was to design and implement a complete, production-grade management and maintenance automation system for donated Windows 11 laptops distributed by Caritas.
- Initial inquiries established requirements for unlinked patron accounts ('User') with zero cloud access, privacy isolation, automated profile resets, default browser/application mappings (Firefox, VLC, Office, LibreOffice, 7-Zip), and network-level ad-blocking (uBlock Origin across all browsers).
- Operational hardening policies were established: continuous power availability (no sleep/hibernation/standby), Defender PUA blocking, SMB1/LLMNR/NetBIOS deprecation, browser credential saving suppression, and USB executable lockdown.
- Inactivity console lock (Option 2) was explicitly rejected by user decision and excluded from all configurations.
- The user requested accessibility for non-technical administrative staff: both a Terminal User Interface (TUI) and a Graphical User Interface (GUI), zero-friction desktop launchers requiring no manual PowerShell commands or execution policy changes, automated 1-click onboarding for new laptops, an in-place self-updater checking GitHub with fast-fail offline timeouts, and an automated GitHub Actions release workflow.
- Subsequent refinement: Explicit rejection of deploying files to direct subfolders of `C:\` (such as `C:\Caritas`). The system was refactored so that deployment is completely portable and location-independent (e.g. directly on the administrative user's desktop `Desktop\CaritasScripts`), with root launchers (`Caritas-Verwaltung.cmd`, `Caritas-Verwaltung-TUI.cmd`), dynamic path resolution via `$PSScriptRoot`, and documentation in `README.md` updated to describe downloading directly from GitHub Releases without referencing WinRM development tooling.

## 2. Active Intent & Delivered Artifacts
All modules, launchers, and deployment artifacts are authored, validated, and verified on the target hardware (`CARITAS-X1-1`, Windows 11 Pro 64-bit):

1. **Native Graphical User Interface (GUI):**
   - File: `scripts/Caritas-ControlCenter-GUI.ps1`
   - Framework: 100% native .NET Windows Presentation Framework (WPF) with zero external runtime dependencies.
   - Design: Tech-wear professional dark palette ("Bioluminescent Night": `#121212` background, `#1E1E1E` panels, `#4ADE80` Digital Fern primary accents, `#EF4444` danger reset accents).
   - Dynamic Paths: Resolves `$scriptDir`, `$configDir`, and `$logDir` relative to `$PSScriptRoot` without any hardcoded root drive dependencies.
   - Concurrency: Background runspaces with thread-safe `ConcurrentQueue` and `DispatcherTimer` polling every 50 ms. Prevents UI thread freezing during long-running tasks.
   - Interactive Elements: Action cards for 1-Click Erst-Einrichtung, system maintenance, configuration, patron reset, live console box with auto-scrolling, process cancellation button, and fast-fail GitHub update badge.

2. **Interactive Terminal User Interface (TUI):**
   - File: `scripts/Caritas-ControlCenter.ps1`
   - Single-key navigation menu, unattended onboarding support (`-RunOnboardingUnattended`), audit log viewer for local `logs\`, fast-fail update checker (2.5 s timeout), and bidirectional handoff to the GUI via option `[8]`.

3. **Zero-Friction Desktop Launchers:**
   - Files: `Caritas-Verwaltung.cmd`, `Caritas-Verwaltung-TUI.cmd` (at root and mirrored in `setup/`)
   - Dynamically resolves script paths relative to `%~dp0`. Executes PowerShell in Single-Thread Apartment mode with per-process execution policy bypass (`-ExecutionPolicy Bypass`), invoking elevated UAC prompts without requiring manual PowerShell interaction.
   - Desktop Shortcuts: `Caritas Verwaltung.lnk` and `Caritas Verwaltung (Terminal).lnk` point directly to the local folder on `C:\Users\carit\Desktop\CaritasScripts`.

4. **1-Step Desktop Environment Provisioner:**
   - File: `setup/Install-CaritasEnvironment.ps1`
   - Initializes local subdirectories (`config`, `logs`) in place without creating folders on `C:\`, and creates elevated desktop shortcuts pointing to the local launchers.

5. **GitHub Release Automation:**
   - File: `.github/workflows/release.yml`
   - Triggers on tag push (`v*.*.*`), packages `CaritasScripts.zip` with root launchers and subdirectories, generates `CaritasScripts.zip.sha256` checksums, and attaches assets to GitHub Releases.

6. **Documentation & User Guide:**
   - File: `README.md`
   - Completely rewritten to guide volunteers and administrators through local setup via GitHub Releases: downloading `CaritasScripts.zip`, extracting to Desktop, double-clicking `Caritas-Verwaltung.cmd`, and clicking 1-Click Erst-Einrichtung. All WinRM and `C:\Caritas` mentions removed.

## 3. Remote Verification & Hardware Testing
- Target Host: `10.106.81.35` (`CARITAS-X1-1`), Windows 11 Pro 64-bit Build 26100.
- All PowerShell scripts parsed and validated via AST parser with zero errors.
- `C:\Caritas` directory completely removed and verified absent (`Test-Path C:\Caritas` -> `False`).
- Complete suite deployed to `C:\Users\carit\Desktop\CaritasScripts\`.
- Scheduled tasks `Caritas-ResetUserSession` and `Caritas-ResetUserOnBoot` updated to point to `C:\Users\carit\Desktop\CaritasScripts\scripts\Reset-CaritasUserProfile.ps1`.
- Registry policy `DefaultAssociationsConfiguration` updated to `C:\Users\carit\Desktop\CaritasScripts\config\AppAssociations.xml` with Authenticated Users read ACLs.
- Desktop shortcuts on `C:\Users\carit\Desktop` verified pointing to `C:\Users\carit\Desktop\CaritasScripts\Caritas-Verwaltung.cmd`.
- WinRM left active and functional on target machine per user instructions.

## 4. Pending Decisions & Next Steps
- Commit changes and tag/push release update (e.g. `v1.0.1`) to GitHub repository `Adrixan/CaritasLaptops-Management-Scripts` to publish the updated packaging bundle.
