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
  - Root cause was Windows PowerShell 5.1 interpreting UTF-8 `.ps1` files lacking a Byte Order Mark (BOM) as ANSI (Windows-1252), causing all multibyte German umlauts (`ä, ö, ü, Ä, Ö, Ü, ß`) and Unicode symbols (`⚡, ★, •, ▶, ✕`) to be read as mojibake (`Ã¤, Ã¶, Ã¼, â¶, â`).
  - Child asynchronous runspaces also defaulted to system OEM encoding rather than UTF-8 when streaming process output.
- GUI Asynchronous Process Runner Deadlock Resolution:
  - User reported initiating "Sitzung von 'User' zurücksetzen" at 10:55:53 in the GUI, with the task still showing as running after several minutes.
  - Remote investigation on hardware CARITAS-X1-1 revealed that Reset-CaritasUserProfile.ps1 completed successfully in 5 seconds (10:55:54 to 10:55:59).
  - Root cause identified: The GUI runner in scripts/Caritas-ControlCenter-GUI.ps1 used synchronous stream reading while (-not $proc.StandardOutput.EndOfStream) { $proc.StandardOutput.ReadLine() }. In interactive desktop sessions, child processes or console subsystems inherit the stdout pipe's write handle. In .NET, EndOfStream blocks indefinitely until every write handle across the OS is closed, even if the primary process has already terminated.
  - Resolution implemented: Replaced synchronous stream reading with asynchronous event-driven reading (Register-ObjectEvent on OutputDataReceived with BeginOutputReadLine()) paired with timed process polling ($proc.WaitForExit(250)). This eliminates pipe handle deadlocks, guarantees immediate task completion reporting, and cleanly unregisters events upon exit.
- Major UI & Execution Architecture Redesign (v1.0.6):
  - Implemented automatic Windows logon (Autologon) for standard account 'User' across setup, defaults, and profile reset scripts.
  - Rebranded GUI styling to authentic Caritas Corporate Identity (Caritas Red #C41230, accessible white/light gray surfaces, high contrast).
  - Eliminated raw terminal shell view, replacing it with a Progress & Status Dashboard featuring a prominent progress bar, percentage badge, step counters, and milestone feed.
  - Enabled scalable layout with min boundaries (960x620) and a dedicated close button.
  - Fixed in-place update version comparison to strictly check if remote version is newer via System.Version.
  - Replaced anonymous pipe streaming with file-redirected process execution and shared reading (FileShare.ReadWrite), eliminating all pipe deadlocks.
  - Enhanced script verbosity with explicit numbered stages ([Schritt 1/6] to [Schritt 6/6]).
- Patron Password Synchronization & Discord Eradication (v1.0.7):
  - Addressed "password is wrong" error when resetting account 'User': synchronized local SAM account password to 'Caritas2412!' and updated Winlogon DefaultPassword across Install-CaritasEnvironment.ps1, Reset-CaritasUserProfile.ps1, and Configure-CaritasDefaults.ps1.
  - Eradicated Discord and Discord System Helper: identified machine-wide Squirrel installer at C:\ProgramData\SquirrelMachineInstalls\Discord.exe invoked via HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run on every logon. Built full purge routines into Install-CaritasEnvironment.ps1, Reset-CaritasUserProfile.ps1, and Sync-CaritasSoftware.ps1.

## 2. Active Intent & Delivered Artifacts
All modules, launchers, and deployment artifacts are authored, validated, and verified on the target hardware (`CARITAS-X1-1`, Windows 11 Pro 64-bit):

1. **Patron Password Synchronization & Auto-Logon:**
   - Scripts: `setup/Install-CaritasEnvironment.ps1`, `scripts/Reset-CaritasUserProfile.ps1`, `scripts/Configure-CaritasDefaults.ps1`.
   - Local SAM user `User` configured with password `Caritas2412!` (`PasswordNeverExpires = $true`).
   - Winlogon credentials stamped with `AutoAdminLogon = 1`, `DefaultUserName = User`, `DefaultPassword = Caritas2412!`, `ForceAutoLogon = 1`.
   - Verified active and authenticated via .NET PrincipalContext on `CARITAS-X1-1`.

2. **Discord & Discord System Helper Complete Eradication:**
   - Scripts: `setup/Install-CaritasEnvironment.ps1`, `scripts/Sync-CaritasSoftware.ps1`, `scripts/Reset-CaritasUserProfile.ps1`.
   - Eliminates machine-wide installer `C:\ProgramData\SquirrelMachineInstalls\Discord.exe`.
   - Scrubs autostart `Run` registry keys in `HKLM:\SOFTWARE\WOW6432Node\...` and `HKLM:\SOFTWARE\...`.
   - Uninstalls per-user installations across `C:\Users\*\AppData\Local\Discord` and `Roaming\discord`.
   - Scrubs desktop and Start Menu shortcuts across all user profiles and Public.
   - Verified 0 processes, 0 installer files, and 0 registry keys on `CARITAS-X1-1`.

3. **UTF-8 with Byte Order Mark (BOM) Standardization:**
   - Files: All 10 PowerShell scripts in `scripts/` and `setup/` prepended with standard 3-byte UTF-8 BOM (`0xEF, 0xBB, 0xBF`).
   - Guarantees Windows PowerShell 5.1 (`powershell.exe`) and PowerShell 7+ reliably recognize UTF-8 encoding across all Windows language editions.
   - Eliminates all mojibake in XAML string parsing, WPF Window construction, button labels, cards, text blocks, tooltips, and MessageBox dialogue boxes.

4. **Console & Pipeline UTF-8 Stream Synchronization:**
   - Script: `scripts/Caritas-ControlCenter-GUI.ps1`, `scripts/Caritas-ControlCenter.ps1`, `setup/Install-CaritasEnvironment.ps1`, and all module scripts.
   - Configured `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` and `$OutputEncoding = [System.Text.Encoding]::UTF8` at script initialization.
   - Asynchronous Engine: Configured `$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8` in `Start-AsyncScript`, and injected UTF-8 console output encoding into child PowerShell process invocations to guarantee live console output stream decoding without corruption.
   - Log Writing: Added `-Encoding UTF8` to all `Add-Content` calls in logging functions (`Write-CCLog`, `Write-SyncLog`, `Write-HardeningLog`, `Write-DefaultsLog`, `Write-UserResetLog`, `Write-MaintLog`).

5. **OOBE Privacy Setup Suppression & Privacy Defaults:**
   - Script: `scripts/Configure-CaritasHardening.ps1`
   - OOBE Suppression: Configured `DisablePrivacyExperience = 1` in `HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE`, `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`, and `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System`.
   - Animation & SCOOBE Bypass: Set `EnableFirstLogonAnimation = 0`, `ScoobeSystemSettingEnabled = 0`, `ShowWindowsProvider = 0`, and `RestartApps = 0` (preventing automatic reopening of apps on sign-in).
   - Strict Sensory & Input Privacy: Set `DisableLocation = 1`, `DisableLocationScripting = 1`, `DisableSensors = 1`, and forced `ConsentStore\location` to `Deny`. Restricted implicit inking and text collection (`AllowInputPersonalization = 0`, `RestrictImplicitInkCollection = 1`, `RestrictImplicitTextCollection = 1`).
   - Find My Device & Speech: Set `AllowFindMyDevice = 0` and `AllowSpeechModelUpdate = 0`.
   - Hive Stamping: Automatically stamped privacy acceptance flags and disabled Content Delivery Manager suggestions across `.DEFAULT` and all active user registry hives (`S-1-5-21*`).

6. **Firefox Enterprise Pre-Configuration & Autostart Suppression:**
   - Scripts: `scripts/Configure-CaritasDefaults.ps1`, `scripts/Configure-CaritasMaintenanceAndPrivacy.ps1`
   - Enterprise Policies: Deployed `C:\Program Files\Mozilla Firefox\distribution\policies.json` and mirrored HKLM registry policies locking `browser.aboutwelcome.enabled: false`, `trailhead.firstrun.didSeeAboutWelcome: true`, `doh-rollout.doneFirstRun: true`, `OverrideFirstRunPage: ""`, `OverridePostUpdatePage: ""`, `DontCheckDefaultBrowser: 1`, `DisableProfileImport: 1`, `DisablePocket: 1`, and `DisableTelemetry: 1`.
   - Autostart Lockdown: Locked `browser.startup.windowsLaunchOnLogin.enabled: false`. Scrubbed Firefox autostart entries from `Run` keys across HKLM, WOW6432Node, HKCU, and all mounted user hives (`S-1-5-21*`). Disabled Firefox background maintenance scheduled tasks.

7. **Desktop Shortcut Launcher & Quoting Fix:**
   - Files: `Caritas-Verwaltung.cmd`, `Caritas-Verwaltung-TUI.cmd` (at root and in `setup/`)
   - Fixed argument escaping by passing a native PowerShell array `@('-Sta', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '%TARGET_SCRIPT%')`, preventing argument truncation or empty-string parsing.
   - Updated provisioner `setup/Install-CaritasEnvironment.ps1` to detect active local administrator profiles dynamically and deploy shortcuts to `C:\Users\CaritasAdmin\Desktop`.

8. **Strictly On-Demand Patron Profile Reset:**
   - Script: `scripts/Reset-CaritasUserProfile.ps1`
   - Unprivileged Execution Mechanism: Elevated Scheduled Task `Caritas-ResetUserSession` under `NT AUTHORITY\SYSTEM` with security descriptor `(A;;0x12019f;;;BU)` and file ACL `icacls *S-1-5-32-545:(RX)` on the task definition.
   - Public Desktop Shortcut: `C:\Users\Public\Desktop\Sitzung zurücksetzen.lnk` pointing to `schtasks.exe /run /tn "Caritas-ResetUserSession"`.
   - Profiles persist across routine reboots, logouts, and shutdowns.

9. **Native Control Centers (GUI & TUI):**
   - GUI: `scripts/Caritas-ControlCenter-GUI.ps1` (WPF/XAML, Caritas CI with Caritas Red #C41230, live Progress & Status Dashboard, scalable layout, dedicated exit option, non-blocking file-redirected runner).
   - TUI: `scripts/Caritas-ControlCenter.ps1` (single-key interaction, audit log viewer, unattended switch, strictly newer version update logic).
   - Version metadata bumped to `1.0.7` in `version.json`.

## 3. Remote Verification & Hardware Testing
- Target Host: `10.106.81.35` (`CARITAS-X1-1`), Windows 11 Pro 64-bit Build 26100.
- Active Administrator: `CaritasAdmin`.
- Suite Location: `C:\Users\CaritasAdmin\Desktop\CaritasScripts\`.
- Autologon & Password Verification: Verified `User` credentials `Caritas2412!` via `System.DirectoryServices.AccountManagement.PrincipalContext` return `Valid: True`. Confirmed `AutoAdminLogon = 1`, `DefaultUserName = User`, `DefaultPassword = Caritas2412!`, `ForceAutoLogon = 1` in `Winlogon`.
- Discord Eradication Verification: Verified 0 running Discord/DiscordSystemHelper processes, Squirrel machine installer purged, HKLM WOW64 Run key removed, and local user AppData Discord directories purged.
- Live Reset & Provisioning Execution: Successfully ran `Install-CaritasEnvironment.ps1` and `Reset-CaritasUserProfile.ps1` on physical laptop hardware.
- UTF-8 BOM Verification: Confirmed remote PowerShell 5.1 AST parser decodes all scripts without errors.

## 4. Pending Decisions & Next Steps
- Commit repository changes, tag `v1.0.7`, and push to GitHub repository `Adrixan/CaritasLaptops-Management-Scripts` to trigger the automated release workflow.
