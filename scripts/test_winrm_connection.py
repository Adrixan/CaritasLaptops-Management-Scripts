#!/usr/bin/env python3
"""
Test WinRM connectivity and command execution from Linux to Windows laptop.
Usage:
    uv run --with pypsrp scripts/test_winrm_connection.py [--host 10.106.81.35] [--user CaritasAdmin]
"""
import argparse
import getpass
import os
import sys
from pypsrp.client import Client


def main() -> int:
    parser = argparse.ArgumentParser(description="Test WinRM connectivity to target Windows host.")
    parser.add_argument("--host", default="10.106.81.35", help="Target IP address or hostname (default: 10.106.81.35)")
    parser.add_argument("--port", type=int, default=5985, help="WinRM port (default: 5985)")
    parser.add_argument("--user", default="CaritasAdmin", help="Local administrative username (default: CaritasAdmin)")
    parser.add_argument("--password", default=None, help="Password (prompted if omitted or set via WINRM_PASSWORD env var)")
    args = parser.parse_args()

    password = args.password or os.environ.get("WINRM_PASSWORD")
    if not password:
        password = getpass.getpass(f"Enter password for {args.user}@{args.host}: ")

    print(f"Connecting to http://{args.host}:{args.port}/wsman as {args.user}...")
    try:
        client = Client(
            server=args.host,
            port=args.port,
            username=args.user,
            password=password,
            ssl=False,
            connection_timeout=5,
            read_timeout=15,
        )

        print("[*] Executing test command: whoami /groups...")
        stdout, stderr, rc = client.execute_cmd("whoami /groups")
        if rc == 0:
            print("[+] Connection successful! Output:")
            for line in stdout.splitlines():
                if "S-1-5-32-544" in line or "Administrators" in line or "Mandatory Label" in line:
                    print(f"    {line}")
            print(f"[+] Return code: {rc}")
            return 0
        else:
            print(f"[-] Command failed with return code {rc}")
            if stderr:
                print(f"[-] Error: {stderr.strip()}")
            return rc
    except Exception as exc:
        print(f"[-] WinRM connection failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
