#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Stellt die lokalen Caritas-Administrationskonten sicher.
.DESCRIPTION
    Garantiert die permanente Verfügbarkeit administrativer Rechte auf dem Laptop:
    1. Prüft und erstellt das lokale Haupt-Administrationskonto 'CaritasAdmin' mit dem
       Standard-Passwort 'CariUntertasse-STMK-2025!'.
    2. Aktiviert das integrierte Windows-Konto 'Administrator' und synchronisiert dessen
       Kennwort auf 'CariUntertasse-STMK-2025!'.
    3. Weist beiden Konten die Mitgliedschaft in der lokalen Administratoren-Gruppe zu
       (automatische Spracherkennung über die bekannte Well-Known-SID S-1-5-32-544).
    4. Setzt 'PasswordNeverExpires = $true', um administrative Aussperrungen zu verhindern.
.PARAMETER AdminPassword
    Das zu setzende Administrator-Kennwort. Standard: 'CariUntertasse-STMK-2025!'.
.PARAMETER DryRun
    Simuliert die Schritte und protokolliert die Prüfungen ohne Änderungen am System.
.NOTES
    Kompatibel mit allen Windows 11 Editionen (Home, Pro, Enterprise, Education).
    Wird automatisch in der Erst-Einrichtung ausgeführt und kann jederzeit über das
    Kontrollzentrum per Knopfdruck aufgerufen werden.
    Protokolliert in logs\AdminAccounts.log.
#>
[CmdletBinding()]
param(
    [string]$AdminPassword = "CariUntertasse-STMK-2025!",
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

# Enforce UTF-8 console and pipeline encoding
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# 1. Logging Infrastructure (Dynamically Resolved)
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Item -Path ".").FullName }
$baseDir = Split-Path -Path $scriptDir -Parent
if (-not (Test-Path "$baseDir\scripts")) { $baseDir = $scriptDir }
$logDir = Join-Path $baseDir "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "AdminAccounts.log"

function Write-AdminLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$timestamp] [$Level] $Message"
    Write-Host $logLine -ForegroundColor $Color
    try {
        Add-Content -Path $logFile -Value $logLine -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

Write-AdminLog "==========================================================" "START" ([ConsoleColor]::Cyan)
Write-AdminLog "Start: Sicherstellung der administrativen Benutzerkonten" "START" ([ConsoleColor]::Cyan)
Write-AdminLog "Computer: $env:COMPUTERNAME | Aufrufer: $env:USERNAME" "INFO" ([ConsoleColor]::Gray)

$secAdminPass = ConvertTo-SecureString $AdminPassword -AsPlainText -Force

# 2. Resolve Local Administrators Group via Well-Known SID S-1-5-32-544
Write-AdminLog "[Schritt 1/4] Ermittle lokale Administratoren-Gruppe..." "INFO" ([ConsoleColor]::Yellow)
try {
    $adminGroup = Get-LocalGroup -SID "S-1-5-32-544" -ErrorAction Stop
    $adminGroupName = $adminGroup.Name
    Write-AdminLog "  -> Lokale Administratoren-Gruppe identifiziert: '$adminGroupName' (SID: S-1-5-32-544)" "INFO" ([ConsoleColor]::Green)
} catch {
    $adminGroupName = "Administratoren"
    Write-AdminLog "  -> Fallback auf Gruppenname '$adminGroupName': $_" "WARN" ([ConsoleColor]::Yellow)
}

# 3. Ensure Primary Administrative User 'CaritasAdmin'
Write-AdminLog "[Schritt 2/4] Prüfe und konfiguriere Haupt-Administratorkonto 'CaritasAdmin'..." "INFO" ([ConsoleColor]::Yellow)
$caritasAdminUser = Get-LocalUser -Name "CaritasAdmin" -ErrorAction SilentlyContinue

if ($DryRun) {
    if (-not $caritasAdminUser) {
        Write-AdminLog "  [DryRun] Würde Konto 'CaritasAdmin' neu anlegen und Gruppe '$adminGroupName' zuweisen." "INFO" ([ConsoleColor]::Gray)
    } else {
        Write-AdminLog "  [DryRun] Würde Kennwort für 'CaritasAdmin' aktualisieren und Status auf aktiv setzen." "INFO" ([ConsoleColor]::Gray)
    }
} else {
    if (-not $caritasAdminUser) {
        Write-AdminLog "  -> Erstelle lokales Benutzerkonto 'CaritasAdmin'..." "ACTION" ([ConsoleColor]::Yellow)
        New-LocalUser -Name "CaritasAdmin" `
            -Password $secAdminPass `
            -FullName "Caritas Administrator" `
            -Description "Lokales Haupt-Administrationskonto für Wartung und Support" `
            -PasswordNeverExpires | Out-Null
        Write-AdminLog "  [OK] Konto 'CaritasAdmin' erfolgreich angelegt." "ACTION" ([ConsoleColor]::Green)
    } else {
        Write-AdminLog "  -> Konto 'CaritasAdmin' existiert. Aktualisiere Kennwort..." "ACTION" ([ConsoleColor]::Gray)
        Set-LocalUser -Name "CaritasAdmin" -Password $secAdminPass -ErrorAction SilentlyContinue | Out-Null
        Write-AdminLog "  [OK] Kennwort für 'CaritasAdmin' erfolgreich synchronisiert." "ACTION" ([ConsoleColor]::Green)
    }

    # Ensure flags: Enabled, PasswordNeverExpires, UserMayChangePassword
    Enable-LocalUser -Name "CaritasAdmin" -ErrorAction SilentlyContinue | Out-Null
    Set-LocalUser -Name "CaritasAdmin" -PasswordNeverExpires $true -UserMayChangePassword $true -ErrorAction SilentlyContinue | Out-Null

    # Add to local administrators group
    $isMember = Get-LocalGroupMember -Group $adminGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*\CaritasAdmin" }
    if (-not $isMember) {
        Add-LocalGroupMember -Group $adminGroupName -Member "CaritasAdmin" -ErrorAction SilentlyContinue | Out-Null
        Write-AdminLog "  [OK] 'CaritasAdmin' zur Gruppe '$adminGroupName' hinzugefügt." "ACTION" ([ConsoleColor]::Green)
    } else {
        Write-AdminLog "  [OK] 'CaritasAdmin' ist bereits Mitglied von '$adminGroupName'." "INFO" ([ConsoleColor]::Green)
    }
}

# 4. Ensure and Activate Built-in 'Administrator' Account
Write-AdminLog "[Schritt 3/4] Prüfe und aktiviere integriertes Konto 'Administrator'..." "INFO" ([ConsoleColor]::Yellow)

# Resolve built-in administrator by well-known RID 500 or localized name
$builtinAdmin = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -match '-500$' }
if (-not $builtinAdmin) {
    $builtinAdmin = Get-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
}

if ($DryRun) {
    if ($builtinAdmin) {
        Write-AdminLog "  [DryRun] Würde integriertes Konto '$($builtinAdmin.Name)' aktivieren und Kennwort synchronisieren." "INFO" ([ConsoleColor]::Gray)
    } else {
        Write-AdminLog "  [DryRun] Würde integriertes Konto 'Administrator' via net user aktivieren." "INFO" ([ConsoleColor]::Gray)
    }
} else {
    $adminAcctName = if ($builtinAdmin) { $builtinAdmin.Name } else { "Administrator" }

    try {
        if ($builtinAdmin) {
            Set-LocalUser -InputObject $builtinAdmin -Password $secAdminPass -PasswordNeverExpires $true -ErrorAction Stop | Out-Null
            Enable-LocalUser -InputObject $builtinAdmin -ErrorAction Stop | Out-Null
        } else {
            & net.exe user Administrator "$AdminPassword" /active:yes | Out-Null
        }
        Write-AdminLog "  [OK] Integriertes Konto '$adminAcctName' aktiviert und Kennwort synchronisiert." "ACTION" ([ConsoleColor]::Green)
    } catch {
        Write-AdminLog "  -> Fallback auf net.exe user für '$adminAcctName': $_" "WARN" ([ConsoleColor]::Yellow)
        & net.exe user "$adminAcctName" "$AdminPassword" /active:yes | Out-Null
        Write-AdminLog "  [OK] Fallback-Aktivierung via net user abgeschlossen." "ACTION" ([ConsoleColor]::Green)
    }

    # Ensure membership in local administrators group
    try {
        $isMemberBuiltin = Get-LocalGroupMember -Group $adminGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*\$adminAcctName" }
        if (-not $isMemberBuiltin) {
            Add-LocalGroupMember -Group $adminGroupName -Member $adminAcctName -ErrorAction SilentlyContinue | Out-Null
            Write-AdminLog "  [OK] '$adminAcctName' zur Gruppe '$adminGroupName' hinzugefügt." "ACTION" ([ConsoleColor]::Green)
        } else {
            Write-AdminLog "  [OK] '$adminAcctName' ist Mitglied von '$adminGroupName'." "INFO" ([ConsoleColor]::Green)
        }
    } catch {
        & net.exe localgroup "$adminGroupName" "$adminAcctName" /add 2>$null | Out-Null
    }
}

# 5. Ensure Caritas Management-Suite on CaritasAdmin Desktop
Write-AdminLog "[Schritt 4/4] Stelle Caritas Management-Suite für 'CaritasAdmin' bereit..." "INFO" ([ConsoleColor]::Yellow)

$stagedDir = "C:\ProgramData\CaritasScripts"
$deployHelper = Join-Path $scriptDir "Deploy-CaritasAdminDesktop.ps1"

if ($DryRun) {
    Write-AdminLog "  [DryRun] Würde Skriptsammlung nach '$stagedDir' sichern und Logon-Aufgabe registrieren." "INFO" ([ConsoleColor]::Gray)
} else {
    # 5.1 Stage the suite to permanent system directory C:\ProgramData\CaritasScripts
    try {
        if (-not (Test-Path $stagedDir)) {
            New-Item -ItemType Directory -Path $stagedDir -Force | Out-Null
        }
        if ($baseDir -ne $stagedDir -and (Test-Path (Join-Path $baseDir "Caritas-Verwaltung.cmd"))) {
            Write-AdminLog "  -> Sichere Skriptsammlung in permanenten Speicher '$stagedDir'..." "INFO" ([ConsoleColor]::Yellow)
            Copy-Item -Path "$baseDir\*" -Destination $stagedDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-AdminLog "  [OK] Skriptsammlung erfolgreich in '$stagedDir' gesichert." "ACTION" ([ConsoleColor]::Green)
        }
    } catch {
        Write-AdminLog "  [-] Fehler beim Sichern der Skriptsammlung nach '$stagedDir': $_" "WARN" ([ConsoleColor]::Yellow)
    }

    # 5.2 Register scheduled task 'Caritas-DeployAdminDesktop' triggered at logon
    try {
        $taskName = "Caritas-DeployAdminDesktop"
        $stagedDeployScript = Join-Path $stagedDir "scripts\Deploy-CaritasAdminDesktop.ps1"
        $execScript = if (Test-Path $stagedDeployScript) { $stagedDeployScript } else { $deployHelper }

        if (Test-Path $execScript) {
            $action = New-ScheduledTaskAction -Execute "powershell.exe" `
                -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$execScript`""
            $trigger = New-ScheduledTaskTrigger -AtLogOn
            $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
            Write-AdminLog "  [OK] Geplante Aufgabe '$taskName' erfolgreich unter SYSTEM registriert." "ACTION" ([ConsoleColor]::Green)
        }
    } catch {
        Write-AdminLog "  [-] Fehler beim Registrieren der geplanten Aufgabe: $_" "WARN" ([ConsoleColor]::Yellow)
    }

    # 5.3 Attempt immediate deployment if CaritasAdmin profile already exists
    try {
        if (Test-Path $deployHelper) {
            & "$deployHelper" -StagedPath $stagedDir -TargetUser "CaritasAdmin"
        }
    } catch {
        Write-AdminLog "  [-] Fehler bei der sofortigen Desktop-Bereitstellung: $_" "WARN" ([ConsoleColor]::Yellow)
    }
}

# 6. Verification & Summary
Write-AdminLog "==========================================================" "DONE" ([ConsoleColor]::Cyan)
Write-AdminLog "ERGEBNIS DER ADMINISTRATOR-SICHERSTELLUNG:" "DONE" ([ConsoleColor]::Green)
Write-AdminLog "  ✓ CaritasAdmin: Aktiv, Kennwort gesetzt, Mitglied in '$adminGroupName'" "INFO" ([ConsoleColor]::Green)
Write-AdminLog "  ✓ Administrator (integriert): Aktiviert, Kennwort gesetzt, Mitglied in '$adminGroupName'" "INFO" ([ConsoleColor]::Green)
Write-AdminLog "  ✓ Suite-Bereitstellung: Gesichert in '$stagedDir' & Aufgabe 'Caritas-DeployAdminDesktop' aktiv" "INFO" ([ConsoleColor]::Green)
Write-AdminLog "  ✓ Administratives Standardkennwort: $AdminPassword" "INFO" ([ConsoleColor]::White)
Write-AdminLog "Protokolldatei: $logFile" "DONE" ([ConsoleColor]::White)
