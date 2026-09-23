#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Disables WinRM and restores system security baselines after development.
.DESCRIPTION
    Tears down the development remote access environment by stopping the WinRM service,
    removing HTTP listeners, disabling firewall openings, restoring UAC remote filtering,
    re-enforcing encryption policies, and disabling or removing the local maintenance admin account.
.PARAMETER AdminUsername
    Name of the local administrator account created for maintenance. Default is "CaritasAdmin".
.PARAMETER DeleteAdminAccount
    If switch is present, permanently removes the user account. If omitted, the account is disabled.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AdminUsername = "CaritasAdmin",

    [Parameter(Mandatory = $false)]
    [switch]$DeleteAdminAccount
)

$ErrorActionPreference = "Stop"

Write-Host "=== Disabling WinRM Development Configuration ===" -ForegroundColor Cyan

# 1. Disable Windows Defender Firewall Inbound Rule
Write-Host "[1/6] Disabling Windows Defender Firewall rules for WinRM..." -ForegroundColor Yellow
$fwRule = Get-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -ErrorAction SilentlyContinue
if ($fwRule) {
    Disable-NetFirewallRule -Name "WINRM-HTTP-In-TCP"
    Write-Host "      Firewall rule 'WINRM-HTTP-In-TCP' disabled." -ForegroundColor Green
} else {
    Write-Host "      No active 'WINRM-HTTP-In-TCP' firewall rule detected." -ForegroundColor Gray
}

# 2. Remove HTTP Listener and Disable PSRemoting
Write-Host "[2/6] Removing WSMan HTTP listeners and disabling PSRemoting..." -ForegroundColor Yellow
try {
    Disable-PSRemoting -Force -ErrorAction SilentlyContinue
    $listeners = Get-ChildItem -Path "WSMan:\localhost\Listener" -ErrorAction SilentlyContinue
    foreach ($listener in $listeners) {
        if ($listener.Keys -contains "Transport=HTTP") {
            Remove-Item -Path "WSMan:\localhost\Listener\$($listener.Name)" -Recurse -Force
            Write-Host "      Removed WSMan HTTP listener." -ForegroundColor Green
        }
    }
} catch {
    Write-Host "      Notice: Error while removing WSMan listener: $_" -ForegroundColor DarkGray
}

# 3. Stop and Demote WinRM Service
Write-Host "[3/6] Stopping and setting WinRM service to Manual..." -ForegroundColor Yellow
Stop-Service -Name WinRM -Force -ErrorAction SilentlyContinue
Set-Service -Name WinRM -StartupType Manual
Write-Host "      WinRM service stopped and startup type set to Manual." -ForegroundColor Green

# 4. Re-enable UAC Remote Filtering
Write-Host "[4/6] Restoring LocalAccountTokenFilterPolicy to secure baseline..." -ForegroundColor Yellow
$systemPolicyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-ItemProperty -Path $systemPolicyPath -Name "LocalAccountTokenFilterPolicy" -Value 0 -Type DWord
Write-Host "      LocalAccountTokenFilterPolicy set to 0 (default UAC filtering restored)." -ForegroundColor Green

# 5. Restore WSMan Service Security Settings
Write-Host "[5/6] Restoring WSMan encryption policies..." -ForegroundColor Yellow
try {
    Set-Item -Path "WSMan:\localhost\Service\AllowUnencrypted" -Value $false -ErrorAction SilentlyContinue
    Write-Host "      AllowUnencrypted set to false." -ForegroundColor Green
} catch {
    Write-Host "      Notice: Could not modify AllowUnencrypted setting: $_" -ForegroundColor DarkGray
}

# 6. Decommission Local Maintenance Account
Write-Host "[6/6] Handling maintenance account '$AdminUsername'..." -ForegroundColor Yellow
$user = Get-LocalUser -Name $AdminUsername -ErrorAction SilentlyContinue
if ($user) {
    if ($DeleteAdminAccount) {
        Remove-LocalUser -Name $AdminUsername
        Write-Host "      Permanently deleted local account '$AdminUsername'." -ForegroundColor Green
    } else {
        Disable-LocalUser -Name $AdminUsername
        Write-Host "      Disabled local account '$AdminUsername' (login prevented)." -ForegroundColor Green
    }
} else {
    Write-Host "      Account '$AdminUsername' not present." -ForegroundColor Gray
}

Write-Host "=== WinRM Tear-down Complete ===" -ForegroundColor Cyan
Write-Host "Remote access is disabled and system security baselines are restored." -ForegroundColor White
