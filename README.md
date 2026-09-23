# CaritasLaptops-Management-Scripts

Everything necessary to keep the freely available Caritas laptops up to speed.

## Repository Structure

```
├── README.md
├── software-inventory.md          # User retention policy checklist ([x] keep / [ ] remove)
├── software-inventory-current.md  # Post-synchronization verified inventory
├── scripts/
│   ├── Configure-CaritasHardening.ps1 # Standalone system hardening and power baseline policy
│   ├── generate_inventory.py      # Queries WSMan registry and AppX manifests to rebuild inventory
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
