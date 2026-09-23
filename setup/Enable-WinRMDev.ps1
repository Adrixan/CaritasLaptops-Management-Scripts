#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures and enables WinRM for remote management during development.
.DESCRIPTION
    Enables Windows Remote Management (HTTP port 5985), sets the active network
    category to Private, provisions a local administrator account for Workgroup NTLM
    authentication, disables UAC remote restrictions, and configures Windows Firewall.
.PARAMETER AdminUsername
    Name of the local administrator account to create or verify. Default is "CaritasAdmin".
.PARAMETER AdminPassword
    SecureString password for the local administrator account. If not supplied and the
    user does not exist, an interactive prompt will request it.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AdminUsername = "CaritasAdmin",

    [Parameter(Mandatory = $false)]
    [System.Security.SecureString]$AdminPassword
)

$ErrorActionPreference = "Stop"

Write-Host "=== Enabling WinRM for Development Environment ===" -ForegroundColor Cyan

# 1. Elevate Network Profile to Private
Write-Host "[1/6] Configuring active network profile to Private..." -ForegroundColor Yellow
$profiles = Get-NetConnectionProfile
foreach ($profile in $profiles) {
    if ($profile.NetworkCategory -ne "Private") {
        Set-NetConnectionProfile -InterfaceIndex $profile.InterfaceIndex -NetworkCategory Private
        Write-Host "      Updated interface index $($profile.InterfaceIndex) to Private." -ForegroundColor Green
    } else {
        Write-Host "      Interface index $($profile.InterfaceIndex) already Private." -ForegroundColor Gray
    }
}

# 2. Configure and Start WinRM Service
Write-Host "[2/6] Starting and configuring WinRM service..." -ForegroundColor Yellow
Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM
Enable-PSRemoting -SkipNetworkProfileCheck -Force
Write-Host "      WinRM service active and automatic startup configured." -ForegroundColor Green

# 3. Create or Verify Local Administrator Account
Write-Host "[3/6] Checking local administrative account '$AdminUsername'..." -ForegroundColor Yellow
$existingUser = Get-LocalUser -Name $AdminUsername -ErrorAction SilentlyContinue

if (-not $existingUser) {
    if (-not $AdminPassword) {
        Write-Host "      User '$AdminUsername' does not exist." -ForegroundColor Yellow
        $AdminPassword = Read-Host -Prompt "Enter password for $AdminUsername" -AsSecureString
    }
    New-LocalUser -Name $AdminUsername -Password $AdminPassword -FullName "Caritas Maintenance Administrator" -Description "Dedicated local admin for remote management" | Out-Null
    Add-LocalGroupMember -Group "Administrators" -Member $AdminUsername
    Write-Host "      Created local administrator '$AdminUsername'." -ForegroundColor Green
} else {
    Write-Host "      User '$AdminUsername' already exists." -ForegroundColor Gray
    $groupMembers = Get-LocalGroupMember -Group "Administrators" | Select-Object -ExpandProperty Name
    if ($groupMembers -notcontains $AdminUsername -and $groupMembers -notcontains "$env:COMPUTERNAME\$AdminUsername") {
        Add-LocalGroupMember -Group "Administrators" -Member $AdminUsername
        Write-Host "      Added '$AdminUsername' to Administrators group." -ForegroundColor Green
    }
    if (-not $existingUser.Enabled) {
        Enable-LocalUser -Name $AdminUsername
        Write-Host "      Re-enabled user account '$AdminUsername'." -ForegroundColor Green
    }
}

# 4. Disable UAC Remote Filtering for Local Accounts
Write-Host "[4/6] Setting LocalAccountTokenFilterPolicy to bypass UAC remote token stripping..." -ForegroundColor Yellow
$systemPolicyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-ItemProperty -Path $systemPolicyPath -Name "LocalAccountTokenFilterPolicy" -Value 1 -Type DWord
Write-Host "      LocalAccountTokenFilterPolicy set to 1." -ForegroundColor Green

# 5. Configure WSMan Service Authentication and Encryption
Write-Host "[5/6] Configuring WSMan daemon settings..." -ForegroundColor Yellow
Set-Item -Path "WSMan:\localhost\Service\Auth\Negotiate" -Value $true
Set-Item -Path "WSMan:\localhost\Service\AllowUnencrypted" -Value $true
Write-Host "      Negotiate authentication and transport permissions configured." -ForegroundColor Green

# 6. Verify and Activate Windows Firewall Inbound Rule
Write-Host "[6/6] Verifying Windows Defender Firewall rules for TCP port 5985..." -ForegroundColor Yellow
$fwRule = Get-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -ErrorAction SilentlyContinue
if ($fwRule) {
    Enable-NetFirewallRule -Name "WINRM-HTTP-In-TCP"
    Write-Host "      Firewall rule 'WINRM-HTTP-In-TCP' enabled." -ForegroundColor Green
} else {
    New-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -DisplayName "Windows Remote Management (HTTP-In)" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow | Out-Null
    Write-Host "      Created and enabled firewall rule 'WINRM-HTTP-In-TCP' on TCP 5985." -ForegroundColor Green
}

Write-Host "=== WinRM Development Setup Complete ===" -ForegroundColor Cyan
Write-Host "The laptop is now accessible via WinRM HTTP on port 5985." -ForegroundColor White
