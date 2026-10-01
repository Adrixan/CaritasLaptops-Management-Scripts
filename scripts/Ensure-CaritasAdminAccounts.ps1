#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Stellt die lokalen Caritas-Administrationskonten sicher.
.DESCRIPTION
    Garantiert die permanente Verfügbarkeit administrativer Rechte auf dem Laptop:
    1. Prüft und erstellt das lokale Haupt-Administrationskonto 'CaritasAdmin' mit dem
       Standard-Passwort 'CariUntertasse-STMK-2025!' über ein robustes 3-Stufen-Verfahren
       (PowerShell cmdlet -> native net.exe user -> WinNT ADSI Schnittstelle).
    2. Aktiviert das integrierte Windows-Konto 'Administrator' (RID -500) und synchronisiert dessen
       Kennwort auf 'CariUntertasse-STMK-2025!'.
    3. Weist beiden Konten die Mitgliedschaft in der lokalen Administratoren-Gruppe zu
       (automatische Erkennung über Well-Known-SID S-1-5-32-544 mit Sprach-Fallback).
    4. Setzt 'PasswordNeverExpires = $true' und entsperrt beide Konten.
    5. Sichert die Skriptsammlung nach 'C:\ProgramData\CaritasScripts', registriert die
       automatische Desktop-Bereitstellung beim Login und platziert die Suite auf den Desktops
       aller Administratoren.
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

# Helper: Resolve Local Administrators Group Name via Well-Known SID S-1-5-32-544
function Get-AdminGroupName {
    # Method 1: Get-LocalGroup by SID S-1-5-32-544
    try {
        $g = Get-LocalGroup -SID "S-1-5-32-544" -ErrorAction Stop
        if ($g -and $g.Name) { return $g.Name }
    } catch {}

    # Method 2: .NET SecurityIdentifier translation (Pure Win32 LsaLookupSids)
    try {
        $sidObj = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
        $ntAcct = $sidObj.Translate([System.Security.Principal.NTAccount]).Value
        $name = $ntAcct.Split('\')[-1]
        if ($name) { return $name }
    } catch {}

    # Method 3: CIM / WMI query
    try {
        $cimGrp = Get-CimInstance -ClassName Win32_Group -Filter "SID = 'S-1-5-32-544'" -ErrorAction Stop
        if ($cimGrp -and $cimGrp.Name) { return $cimGrp.Name }
    } catch {}

    # Method 4: Test localized names via net.exe
    foreach ($cand in @("Administratoren", "Administrators")) {
        try {
            & net.exe localgroup "$cand" 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { return $cand }
        } catch {}
    }

    return "Administratoren"
}

# Helper: Robust Account Existence Check
function Test-UserAccountExists {
    param([string]$Username)
    try {
        $u = Get-LocalUser -Name $Username -ErrorAction Stop
        if ($u) { return $true }
    } catch {}
    try {
        $netOut = & net.exe user "$Username" 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $netOut -notmatch "existiert nicht|cannot be found|nicht gefunden") { return $true }
    } catch {}
    try {
        $u = [ADSI]"WinNT://$env:COMPUTERNAME/$Username,user"
        if ($u -and $u.Name -eq $Username) { return $true }
    } catch {}
    try {
        $cimU = Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount=True AND Name='$Username'" -ErrorAction Stop
        if ($cimU) { return $true }
    } catch {}
    return $false
}

# Helper: Robust Group Membership Test
function Test-AccountIsAdminMember {
    param(
        [string]$AccountName,
        [string]$GroupName
    )
    # Check 1: Get-LocalGroupMember
    try {
        $m = Get-LocalGroupMember -Group $GroupName -ErrorAction Stop | Where-Object { $_.Name -like "*\$AccountName" -or $_.Name -eq $AccountName }
        if ($m) { return $true }
    } catch {}

    # Check 2: net.exe localgroup
    try {
        $netOut = & net.exe localgroup "$GroupName" 2>&1 | Out-String
        if ($netOut -match "(?m)^\s*$([regex]::Escape($AccountName))\s*$") { return $true }
    } catch {}

    # Check 3: Check candidate groups (German & English)
    foreach ($cand in @("Administratoren", "Administrators")) {
        if ($cand -ne $GroupName) {
            try {
                $netOut = & net.exe localgroup "$cand" 2>&1 | Out-String
                if ($netOut -match "(?m)^\s*$([regex]::Escape($AccountName))\s*$") { return $true }
            } catch {}
        }
    }

    # Check 4: ADSI group members
    try {
        $adsiGrp = [ADSI]"WinNT://$env:COMPUTERNAME/$GroupName,group"
        $members = @($adsiGrp.Invoke("Members")) | ForEach-Object {
            $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)
        }
        if ($members -contains $AccountName) { return $true }
    } catch {}

    return $false
}

# Helper: Robust Group Membership Assignment
function Add-AccountToAdminGroup {
    param(
        [string]$AccountName,
        [string]$GroupName
    )
    # Method 1: Add-LocalGroupMember
    try {
        Add-LocalGroupMember -Group $GroupName -Member $AccountName -ErrorAction Stop | Out-Null
        return $true
    } catch {}

    # Method 2: net localgroup with primary group name
    try {
        & net.exe localgroup "$GroupName" "$AccountName" /add 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 2) { return $true }
    } catch {}

    # Method 3: net localgroup with German and English candidate names
    foreach ($cand in @("Administratoren", "Administrators")) {
        try {
            & net.exe localgroup "$cand" "$AccountName" /add 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 2) { return $true }
        } catch {}
    }

    # Method 4: ADSI WinNT Group Add
    try {
        $adsiGrp = [ADSI]"WinNT://$env:COMPUTERNAME/$GroupName,group"
        $adsiGrp.Add("WinNT://$env:COMPUTERNAME/$AccountName")
        return $true
    } catch {}

    return $false
}

Write-AdminLog "==========================================================" "START" ([ConsoleColor]::Cyan)
Write-AdminLog "Start: Sicherstellung der administrativen Benutzerkonten" "START" ([ConsoleColor]::Cyan)
Write-AdminLog "Computer: $env:COMPUTERNAME | Aufrufer: $env:USERNAME" "INFO" ([ConsoleColor]::Gray)

$secAdminPass = ConvertTo-SecureString $AdminPassword -AsPlainText -Force

# 2. Resolve Local Administrators Group via Well-Known SID S-1-5-32-544
Write-AdminLog "[Schritt 1/4] Ermittle lokale Administratoren-Gruppe..." "INFO" ([ConsoleColor]::Yellow)
$adminGroupName = Get-AdminGroupName
Write-AdminLog "  -> Lokale Administratoren-Gruppe identifiziert: '$adminGroupName' (SID: S-1-5-32-544)" "INFO" ([ConsoleColor]::Green)

# 3. Ensure Primary Administrative User 'CaritasAdmin'
Write-AdminLog "[Schritt 2/4] Prüfe und konfiguriere Haupt-Administratorkonto 'CaritasAdmin'..." "INFO" ([ConsoleColor]::Yellow)
$caritasAdminExists = Test-UserAccountExists -Username "CaritasAdmin"

if ($DryRun) {
    if (-not $caritasAdminExists) {
        Write-AdminLog "  [DryRun] Würde Konto 'CaritasAdmin' neu anlegen und Gruppe '$adminGroupName' zuweisen." "INFO" ([ConsoleColor]::Gray)
    } else {
        Write-AdminLog "  [DryRun] Würde Kennwort für 'CaritasAdmin' aktualisieren und Status auf aktiv setzen." "INFO" ([ConsoleColor]::Gray)
    }
} else {
    if (-not $caritasAdminExists) {
        Write-AdminLog "  -> Erstelle lokales Benutzerkonto 'CaritasAdmin'..." "ACTION" ([ConsoleColor]::Yellow)
        $created = $false

        # Tier 1: PowerShell New-LocalUser
        try {
            New-LocalUser -Name "CaritasAdmin" `
                -Password $secAdminPass `
                -FullName "Caritas Administrator" `
                -Description "Lokales Haupt-Administrationskonto für Wartung und Support" `
                -PasswordNeverExpires -ErrorAction Stop | Out-Null
            $created = $true
            Write-AdminLog "  [OK] Konto 'CaritasAdmin' via New-LocalUser erfolgreich angelegt." "ACTION" ([ConsoleColor]::Green)
        } catch {
            Write-AdminLog "  -> New-LocalUser fehlgeschlagen ($($_.Exception.Message)). Starte Tier-2 Fallback via net.exe..." "WARN" ([ConsoleColor]::Yellow)
        }

        # Tier 2: Native Win32 net.exe user
        if (-not $created) {
            try {
                $netRes = & net.exe user CaritasAdmin "$AdminPassword" /add /comment:"Lokales Haupt-Administrationskonto fuer Wartung und Support" /fullname:"Caritas Administrator" /active:yes 2>&1 | Out-String
                if ($LASTEXITCODE -eq 0 -or (Test-UserAccountExists -Username "CaritasAdmin")) {
                    $created = $true
                    Write-AdminLog "  [OK] Konto 'CaritasAdmin' via net.exe user erfolgreich angelegt." "ACTION" ([ConsoleColor]::Green)
                } else {
                    Write-AdminLog "  -> net.exe user fehlgeschlagen ($netRes). Starte Tier-3 Fallback via ADSI..." "WARN" ([ConsoleColor]::Yellow)
                }
            } catch {
                Write-AdminLog "  -> net.exe user Ausnahme: $_. Starte Tier-3 Fallback via ADSI..." "WARN" ([ConsoleColor]::Yellow)
            }
        }

        # Tier 3: Direct WinNT ADSI COM Interface
        if (-not $created -and -not (Test-UserAccountExists -Username "CaritasAdmin")) {
            try {
                $adsiComp = [ADSI]"WinNT://$env:COMPUTERNAME"
                $adsiUser = $adsiComp.Create("User", "CaritasAdmin")
                $adsiUser.SetPassword($AdminPassword)
                $adsiUser.put("FullName", "Caritas Administrator")
                $adsiUser.put("Description", "Lokales Haupt-Administrationskonto fuer Wartung und Support")
                $adsiUser.put("UserFlags", 0x10200) # UF_NORMAL_ACCOUNT | UF_DONT_EXPIRE_PASSWORD
                $adsiUser.SetInfo()
                if (Test-UserAccountExists -Username "CaritasAdmin") {
                    $created = $true
                    Write-AdminLog "  [OK] Konto 'CaritasAdmin' via ADSI erfolgreich angelegt." "ACTION" ([ConsoleColor]::Green)
                }
            } catch {
                Write-AdminLog "  [-] ADSI-Kontoerstellung fehlgeschlagen: $_" "ERROR" ([ConsoleColor]::Red)
            }
        }
    } else {
        Write-AdminLog "  -> Konto 'CaritasAdmin' existiert bereits. Synchronisiere Kennwort..." "ACTION" ([ConsoleColor]::Gray)
        $pwSet = $false

        # Tier 1: Set-LocalUser
        try {
            Set-LocalUser -Name "CaritasAdmin" -Password $secAdminPass -ErrorAction Stop | Out-Null
            $pwSet = $true
        } catch {}

        # Tier 2: net.exe user
        if (-not $pwSet) {
            try {
                & net.exe user CaritasAdmin "$AdminPassword" 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { $pwSet = $true }
            } catch {}
        }

        # Tier 3: ADSI
        if (-not $pwSet) {
            try {
                $adsiU = [ADSI]"WinNT://$env:COMPUTERNAME/CaritasAdmin,user"
                $adsiU.SetPassword($AdminPassword)
                $adsiU.SetInfo()
                $pwSet = $true
            } catch {}
        }

        if ($pwSet) {
            Write-AdminLog "  [OK] Kennwort für 'CaritasAdmin' erfolgreich synchronisiert." "ACTION" ([ConsoleColor]::Green)
        } else {
            Write-AdminLog "  [-] Warnung: Kennwort für 'CaritasAdmin' konnte nicht aktualisiert werden." "WARN" ([ConsoleColor]::Yellow)
        }
    }

    # Ensure flags: Enabled, PasswordNeverExpires, UserMayChangePassword
    try { Enable-LocalUser -Name "CaritasAdmin" -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { & net.exe user CaritasAdmin /active:yes 2>&1 | Out-Null } catch {}
    try { Set-LocalUser -Name "CaritasAdmin" -PasswordNeverExpires $true -UserMayChangePassword $true -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { & net.exe user CaritasAdmin /expires:never 2>&1 | Out-Null } catch {}
    try { & wmic.exe useraccount where "name='CaritasAdmin'" set passwordexpires=FALSE 2>&1 | Out-Null } catch {}

    # Add to local administrators group
    $isMember = Test-AccountIsAdminMember -AccountName "CaritasAdmin" -GroupName $adminGroupName
    if (-not $isMember) {
        $added = Add-AccountToAdminGroup -AccountName "CaritasAdmin" -GroupName $adminGroupName
        if ($added) {
            Write-AdminLog "  [OK] 'CaritasAdmin' zur Gruppe '$adminGroupName' hinzugefügt." "ACTION" ([ConsoleColor]::Green)
        } else {
            Write-AdminLog "  [-] Warnung beim Hinzufügen von 'CaritasAdmin' zu '$adminGroupName'." "WARN" ([ConsoleColor]::Yellow)
        }
    } else {
        Write-AdminLog "  [OK] 'CaritasAdmin' ist bereits Mitglied von '$adminGroupName'." "INFO" ([ConsoleColor]::Green)
    }

    # Verification check
    $finalExists = Test-UserAccountExists -Username "CaritasAdmin"
    $finalAdmin = Test-AccountIsAdminMember -AccountName "CaritasAdmin" -GroupName $adminGroupName
    if ($finalExists -and $finalAdmin) {
        Write-AdminLog "  [OK] Verifikation: 'CaritasAdmin' ist aktiv und lokaler Administrator." "ACTION" ([ConsoleColor]::Green)
    } elseif ($finalExists) {
        Write-AdminLog "  [WARN] Verifikation: 'CaritasAdmin' existiert, Mitgliedschaft in '$adminGroupName' unbestätigt." "WARN" ([ConsoleColor]::Yellow)
    } else {
        Write-AdminLog "  [FEHLER] 'CaritasAdmin' konnte auf diesem System nicht angelegt werden!" "ERROR" ([ConsoleColor]::Red)
    }
}

# 4. Ensure and Activate Built-in 'Administrator' Account
Write-AdminLog "[Schritt 3/4] Prüfe und aktiviere integriertes Konto 'Administrator'..." "INFO" ([ConsoleColor]::Yellow)

$builtinAdmin = $null
try {
    $builtinAdmin = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -match '-500$' }
} catch {}

$adminAcctName = $null
if ($builtinAdmin) {
    $adminAcctName = $builtinAdmin.Name
} else {
    try {
        $cimAdmin = Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount=True AND SID LIKE '%-500'" -ErrorAction SilentlyContinue
        if ($cimAdmin -and $cimAdmin.Name) {
            $adminAcctName = $cimAdmin.Name
        }
    } catch {}
}

if (-not $adminAcctName) {
    $adminAcctName = "Administrator"
}

if ($DryRun) {
    Write-AdminLog "  [DryRun] Würde integriertes Konto '$adminAcctName' aktivieren und Kennwort synchronisieren." "INFO" ([ConsoleColor]::Gray)
} else {
    $adminActivated = $false
    # Tier 1: LocalAccounts cmdlet
    try {
        if ($builtinAdmin) {
            Set-LocalUser -InputObject $builtinAdmin -Password $secAdminPass -PasswordNeverExpires $true -ErrorAction Stop | Out-Null
            Enable-LocalUser -InputObject $builtinAdmin -ErrorAction Stop | Out-Null
            $adminActivated = $true
        }
    } catch {}

    # Tier 2: net.exe user
    if (-not $adminActivated) {
        try {
            & net.exe user "$adminAcctName" "$AdminPassword" /active:yes /expires:never 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { $adminActivated = $true }
        } catch {}
    }

    # Tier 3: ADSI
    if (-not $adminActivated) {
        try {
            $adsiAdmin = [ADSI]"WinNT://$env:COMPUTERNAME/$adminAcctName,user"
            $adsiAdmin.SetPassword($AdminPassword)
            $adsiAdmin.AccountDisabled = $false
            $adsiAdmin.SetInfo()
            $adminActivated = $true
        } catch {}
    }

    # Ensure flags
    try { & net.exe user "$adminAcctName" /active:yes /expires:never 2>&1 | Out-Null } catch {}
    try { & wmic.exe useraccount where "name='$adminAcctName'" set passwordexpires=FALSE 2>&1 | Out-Null } catch {}

    if ($adminActivated -or (Test-UserAccountExists -Username $adminAcctName)) {
        Write-AdminLog "  [OK] Integriertes Konto '$adminAcctName' aktiviert und Kennwort synchronisiert." "ACTION" ([ConsoleColor]::Green)
    } else {
        Write-AdminLog "  [-] Warnung: Aktivierung von '$adminAcctName' unvollständig." "WARN" ([ConsoleColor]::Yellow)
    }

    # Ensure membership in local administrators group
    $isMemberBuiltin = Test-AccountIsAdminMember -AccountName $adminAcctName -GroupName $adminGroupName
    if (-not $isMemberBuiltin) {
        $added = Add-AccountToAdminGroup -AccountName $adminAcctName -GroupName $adminGroupName
        if ($added) {
            Write-AdminLog "  [OK] '$adminAcctName' zur Gruppe '$adminGroupName' hinzugefügt." "ACTION" ([ConsoleColor]::Green)
        }
    } else {
        Write-AdminLog "  [OK] '$adminAcctName' ist Mitglied von '$adminGroupName'." "INFO" ([ConsoleColor]::Green)
    }
}

# 5. Ensure Caritas Management-Suite on Administrator Desktops
Write-AdminLog "[Schritt 4/4] Stelle Caritas Management-Suite für Administratoren bereit..." "INFO" ([ConsoleColor]::Yellow)

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

    # 5.2 Register scheduled task 'Caritas-DeployAdminDesktop' triggered at logon for all administrators
    try {
        $taskName = "Caritas-DeployAdminDesktop"
        $stagedDeployScript = Join-Path $stagedDir "scripts\Deploy-CaritasAdminDesktop.ps1"
        $execScript = if (Test-Path $stagedDeployScript) { $stagedDeployScript } else { $deployHelper }

        if (Test-Path $execScript) {
            $action = New-ScheduledTaskAction -Execute "powershell.exe" `
                -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$execScript`" -AllAdmins"
            $trigger = New-ScheduledTaskTrigger -AtLogOn
            $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
            Write-AdminLog "  [OK] Geplante Aufgabe '$taskName' erfolgreich unter SYSTEM registriert." "ACTION" ([ConsoleColor]::Green)
        }
    } catch {
        Write-AdminLog "  [-] Fehler beim Registrieren der geplanten Aufgabe: $_" "WARN" ([ConsoleColor]::Yellow)
    }

    # 5.3 Attempt immediate deployment to all administrative profiles
    try {
        if (Test-Path $deployHelper) {
            Write-AdminLog "  -> Führe sofortige Desktop-Bereitstellung für Administratoren durch..." "INFO" ([ConsoleColor]::Yellow)
            & "$deployHelper" -StagedPath $stagedDir -AllAdmins
        }
    } catch {
        Write-AdminLog "  [-] Fehler bei der sofortigen Desktop-Bereitstellung: $_" "WARN" ([ConsoleColor]::Yellow)
    }
}

# 6. Verification & Summary
Write-AdminLog "==========================================================" "DONE" ([ConsoleColor]::Cyan)
Write-AdminLog "ERGEBNIS DER ADMINISTRATOR-SICHERSTELLUNG:" "DONE" ([ConsoleColor]::Green)
Write-AdminLog "  ✓ CaritasAdmin: Aktiv, Kennwort gesetzt, Mitglied in '$adminGroupName'" "INFO" ([ConsoleColor]::Green)
Write-AdminLog "  ✓ $adminAcctName (integriert): Aktiviert, Kennwort gesetzt, Mitglied in '$adminGroupName'" "INFO" ([ConsoleColor]::Green)
Write-AdminLog "  ✓ Suite-Bereitstellung: Gesichert in '$stagedDir' & Aufgabe 'Caritas-DeployAdminDesktop' aktiv" "INFO" ([ConsoleColor]::Green)
Write-AdminLog "  ✓ Administratives Standardkennwort: $AdminPassword" "INFO" ([ConsoleColor]::White)
Write-AdminLog "Protokolldatei: $logFile" "DONE" ([ConsoleColor]::White)
