#!/usr/bin/env python3
"""
Queries the target Windows laptop over WinRM for all installed software
(Registry Win32, AppX packages, and Winget if present) and outputs
a structured inventory markdown file and JSON file.
"""
import argparse
import getpass
import json
import os
import sys
from pypsrp.client import Client

PS_INVENTORY_SCRIPT = r"""
$ErrorActionPreference = 'SilentlyContinue'

$apps = @()

# 1. 64-bit and 32-bit Registry Uninstall Keys
$regPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

foreach ($path in $regPaths) {
    Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -and -not $_.SystemComponent -and -not $_.ParentKeyName
    } | ForEach-Object {
        $apps += [PSCustomObject]@{
            Name = ($_.DisplayName -as [string]).Trim()
            Version = if ($_.DisplayVersion) { ($_.DisplayVersion -as [string]).Trim() } else { "N/A" }
            Publisher = if ($_.Publisher) { ($_.Publisher -as [string]).Trim() } else { "Unknown" }
            InstallDate = if ($_.InstallDate) { ($_.InstallDate -as [string]).Trim() } else { "" }
            UninstallString = if ($_.UninstallString) { ($_.UninstallString -as [string]).Trim() } else { "" }
            QuietUninstallString = if ($_.QuietUninstallString) { ($_.QuietUninstallString -as [string]).Trim() } else { "" }
            Type = "Win32"
            PackageId = $_.PSChildName
        }
    }
}

# 2. AppX Packages (Exclude framework/dependency packages)
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
    -not $_.IsFramework -and $_.NonRemovable -ne $true -and $_.SignatureKind -ne "System"
} | ForEach-Object {
    $apps += [PSCustomObject]@{
        Name = $_.Name
        Version = $_.Version
        Publisher = $_.PublisherId
        InstallDate = ""
        UninstallString = ""
        QuietUninstallString = ""
        Type = "AppX"
        PackageId = $_.PackageFullName
    }
}

# 3. Output as JSON
$apps | Sort-Object Name -Unique | ConvertTo-Json -Depth 4
"""


def main():
    parser = argparse.ArgumentParser(description="Generate installed software inventory from Windows host.")
    parser.add_argument("--host", default="10.106.81.35", help="Target IP or hostname")
    parser.add_argument("--port", type=int, default=5985, help="WinRM port")
    parser.add_argument("--user", default="CaritasAdmin", help="Username")
    parser.add_argument("--password", default=None, help="Password (prompted if omitted or set via WINRM_PASSWORD env var)")
    parser.add_argument("--output-md", default="software-inventory.md", help="Output Markdown checklist file")
    parser.add_argument("--output-json", default="software-inventory.json", help="Output JSON raw data file")
    args = parser.parse_args()

    password = args.password or os.environ.get("WINRM_PASSWORD")
    if not password:
        password = getpass.getpass(f"Enter password for {args.user}@{args.host}: ")

    print(f"Connecting to http://{args.host}:{args.port}/wsman as {args.user}...")
    client = Client(server=args.host, port=args.port, username=args.user, password=password, ssl=False, read_timeout=60)

    print("Querying installed software inventory...")
    output, streams, had_errors = client.execute_ps(PS_INVENTORY_SCRIPT)

    if had_errors:
        for err in streams.error:
            print(f"PS Warning/Error: {err}", file=sys.stderr)

    raw_json = output.strip()
    if not raw_json:
        print("Error: No data returned from host.", file=sys.stderr)
        return 1

    try:
        software_list = json.loads(raw_json)
        if isinstance(software_list, dict):
            software_list = [software_list]
    except Exception as exc:
        print(f"Error parsing JSON output: {exc}", file=sys.stderr)
        print("Raw output start:", raw_json[:300])
        return 1

    print(f"Successfully retrieved {len(software_list)} software entries.")

    # Save JSON raw inventory
    with open(args.output_json, "w", encoding="utf-8") as f:
        json.dump(software_list, f, indent=2, ensure_ascii=False)
    print(f"Saved raw inventory to {args.output_json}")

    # Categorize items: Win32 vs AppX
    win32_apps = [s for s in software_list if s.get("Type") == "Win32"]
    appx_apps = [s for s in software_list if s.get("Type") == "AppX"]

    # Sort alphabetically by Name
    win32_apps.sort(key=lambda x: x.get("Name", "").lower())
    appx_apps.sort(key=lambda x: x.get("Name", "").lower())

    # Build Markdown file with interactive checkboxes [x] KEEP vs [ ] REMOVE
    with open(args.output_md, "w", encoding="utf-8") as f:
        f.write("# Software Inventory and Retention Policy\n\n")
        f.write(f"Target Host: `{args.host}` (Caritas-X1-1)\n\n")
        f.write("## Instructions\n")
        f.write("Review the software list below. Use the checkboxes to choose what should remain installed:\n")
        f.write("- `[x]` = **KEEP** installed on the laptop.\n")
        f.write("- `[ ]` = **REMOVE / UNINSTALL** during automated cleanup.\n\n")
        f.write("By default, essential system drivers, runtimes, and baseline utilities are marked `[x]`, while typical preinstalled bloatware or consumer apps are left unchecked or marked for review.\n\n")

        f.write(f"## Desktop & Win32 Applications ({len(win32_apps)} items)\n\n")
        f.write("| Action | Application Name | Version | Publisher | Type |\n")
        f.write("| :---: | :--- | :--- | :--- | :---: |\n")
        for app in win32_apps:
            name = app.get("Name", "").replace("|", "-")
            version = app.get("Version", "").replace("|", "-")
            publisher = app.get("Publisher", "").replace("|", "-")
            # Default heuristics for keeping runtimes/drivers
            keep = "[x]"
            lower_name = name.lower()
            if any(term in lower_name for term in ["game", "trial", "promo", "candy", "tiktok", "spotify"]):
                keep = "[ ]"
            f.write(f"| {keep} | {name} | {version} | {publisher} | Win32 |\n")

        f.write(f"\n## AppX / Modern Windows Apps ({len(appx_apps)} items)\n\n")
        f.write("| Action | Package Name | Version | Publisher ID | Type |\n")
        f.write("| :---: | :--- | :--- | :--- | :---: |\n")
        for app in appx_apps:
            name = app.get("Name", "").replace("|", "-")
            version = app.get("Version", "").replace("|", "-")
            publisher = app.get("Publisher", "").replace("|", "-")
            keep = "[x]"
            lower_name = name.lower()
            # Bloatware heuristics
            if any(term in lower_name for term in ["candycrush", "solitaire", "xbox", "zune", "bing", "feedback", "cortana", "gethelp", "quickassist", "yourphone", "people", "communications"]):
                keep = "[ ]"
            f.write(f"| {keep} | {name} | {version} | {publisher} | AppX |\n")

        f.write("\n---\n")
        f.write("### Next Steps\n")
        f.write("1. Open this file and adjust the checkboxes `[x]` (Keep) and `[ ]` (Remove).\n")
        f.write("2. Notify the assistant once selections are made.\n")
        f.write("3. An automated uninstallation script will parse this file and remove all unchecked applications.\n")

    print(f"Generated Markdown inventory: {args.output_md}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
