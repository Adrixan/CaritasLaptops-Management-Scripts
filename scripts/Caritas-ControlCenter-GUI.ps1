#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Caritas Laptop Management Suite - Graphical User Interface (GUI).
.DESCRIPTION
    Native Windows Presentation Framework (WPF) administrative console for
    managing, hardening, updating, and provisioning Caritas laptops.
    Features:
    - Caritas Corporate Identity (Caritas-Rot #C41230, accessible layout).
    - Progress & Status Dashboard with real-time progress bar and milestone feed (no raw shell view).
    - Fully scalable responsive layout with explicit close option.
    - Non-blocking file-redirected background task execution engine (zero pipe deadlocks).
    - Strict version checking for self-updates (only offers updates if remote is newer).
    - Live step detection and substep tracking for all actions.
.NOTES
    Compatible with Windows 10 and Windows 11 (Home, Pro, Enterprise, Education).
    Standardized on UTF-8 with Byte Order Mark (BOM).
#>

# 1. Enforce STA (Single-Threaded Apartment) for WPF
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Start-Process powershell.exe -ArgumentList @('-Sta', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    exit
}

# 2. Enforce Administrator Privileges
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @('-Sta', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    exit
}

# Enforce UTF-8 console and pipeline encoding
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# Add required WPF and WinForms assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# 3. Path & Environment Initialization
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Item -Path ".").FullName }
$baseDir = Split-Path -Path $scriptDir -Parent
if (-not (Test-Path "$baseDir\scripts")) { $baseDir = $scriptDir }
$logDir = Join-Path $baseDir "logs"
$configDir = Join-Path $baseDir "config"
$stagingDir = Join-Path $env:TEMP "CaritasUpdateStaging"
$localVersionFile = Join-Path $baseDir "version.json"

foreach ($dir in @($logDir, $configDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

$logFile = Join-Path $logDir "ControlCenter.log"

function Write-CCLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$timestamp] [$Level] $Message"
    try {
        Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

function Get-LocalVersion {
    if (Test-Path $localVersionFile) {
        try {
            $meta = Get-Content -Path $localVersionFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($meta.version) { return $meta.version }
        } catch {}
    }
    return "1.0.6"
}

# Version comparison function (strictly checks if remote is newer)
function Test-IsNewerVersion {
    param([string]$LocalVersion, [string]$RemoteVersion)
    try {
        $cleanLocal = ($LocalVersion -replace '[^0-9\.]', '').Trim('.')
        $cleanRemote = ($RemoteVersion -replace '[^0-9\.]', '').Trim('.')
        if (-not $cleanLocal -or -not $cleanRemote) { return $false }
        while (($cleanLocal.Split('.').Count) -lt 2) { $cleanLocal += ".0" }
        while (($cleanRemote.Split('.').Count) -lt 2) { $cleanRemote += ".0" }
        $vLocal = [System.Version]$cleanLocal
        $vRemote = [System.Version]$cleanRemote
        return ($vRemote -gt $vLocal)
    } catch {
        return $false
    }
}

# 4. Asynchronous Non-Blocking Task Execution Engine (File-Redirected)
$global:activeProcess = $null
$global:activeProgressLog = $null
$global:pollTimer = $null
$global:taskStartTime = $null
$global:taskFilePosition = 0
$global:taskTotalSteps = 0
$global:taskCurrentStep = 0
$global:activeTaskName = ""
$global:activeTargetLog = ""

function Start-AsyncScript {
    param(
        [string]$ScriptFile,
        [string]$Arguments = "",
        [string]$TaskName = "Vorgang",
        [string]$TargetLog = ""
    )

    if ($global:activeProcess -and (-not $global:activeProcess.HasExited)) {
        [System.Windows.MessageBox]::Show(
            "Ein anderer Vorgang wird derzeit noch ausgeführt. Bitte warten Sie, bis dieser abgeschlossen ist.",
            "Vorgang aktiv",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        ) | Out-Null
        return
    }

    # Reset UI State
    $pnlActivityFeed.Children.Clear()
    $progressBar.Value = 0
    $lblProgressPercent.Text = "0%"
    $global:taskTotalSteps = 0
    $global:taskCurrentStep = 0
    $global:activeTaskName = $TaskName
    $global:activeTargetLog = $TargetLog

    Set-UIExecutionState -Running $true -TaskTitle $TaskName -StatusText "Wird vorbereitet..."

    # Generate unique progress communication file
    $taskId = [Guid]::NewGuid().ToString("N").Substring(0, 8)
    $progressLog = Join-Path $logDir "TaskProgress_$taskId.log"
    $global:activeProgressLog = $progressLog
    $global:taskFilePosition = 0
    $global:taskStartTime = [System.Diagnostics.Stopwatch]::StartNew()

    Write-CCLog "GUI launched task: $TaskName ($ScriptFile $Arguments)"
    Add-ActivityItem -Message "Vorgang '$TaskName' gestartet um $((Get-Date).ToString('HH:mm:ss'))" -Type "Action"

    # Start child process with stdout redirected to file (eliminates anonymous pipe deadlocks)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NonInteractive -NoProfile -ExecutionPolicy Bypass -Command `"try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}; `$OutputEncoding = [System.Text.Encoding]::UTF8; & { & '$ScriptFile' $Arguments } *>&1 | Out-File -FilePath '$progressLog' -Encoding utf8`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        $global:activeProcess = $proc
    } catch {
        Set-UIExecutionState -Running $false -TaskTitle $TaskName -StatusText "Fehler beim Starten: $_" -Success $false
        Add-ActivityItem -Message "[FEHLER] Prozessstart fehlgeschlagen: $_" -Type "Error"
        return
    }

    # UI Dispatcher polling timer (every 100 ms)
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(100)
    $timer.Add_Tick({
        # Read newly written lines from progress file
        if ($global:activeProgressLog -and (Test-Path $global:activeProgressLog)) {
            try {
                $fs = [System.IO.File]::Open($global:activeProgressLog, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                if ($fs.Length -gt $global:taskFilePosition) {
                    $fs.Seek($global:taskFilePosition, [System.IO.SeekOrigin]::Begin) | Out-Null
                    $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
                    while (-not $sr.EndOfStream) {
                        $line = $sr.ReadLine()
                        if ($line -and $line.Trim()) {
                            Process-ProgressLine -Line $line.Trim()
                        }
                    }
                    $global:taskFilePosition = $fs.Position
                    $sr.Dispose()
                }
                $fs.Dispose()
            } catch {}
        }

        # Check process termination
        if ($global:activeProcess -and $global:activeProcess.HasExited) {
            $timer.Stop()
            $global:pollTimer = $null
            $exitCode = $global:activeProcess.ExitCode
            $elapsedSec = [math]::Round($global:taskStartTime.Elapsed.TotalSeconds, 1)

            # Flush remaining lines from log
            if ($global:activeProgressLog -and (Test-Path $global:activeProgressLog)) {
                try {
                    $fs = [System.IO.File]::Open($global:activeProgressLog, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    if ($fs.Length -gt $global:taskFilePosition) {
                        $fs.Seek($global:taskFilePosition, [System.IO.SeekOrigin]::Begin) | Out-Null
                        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
                        while (-not $sr.EndOfStream) {
                            $line = $sr.ReadLine()
                            if ($line -and $line.Trim()) {
                                Process-ProgressLine -Line $line.Trim()
                            }
                        }
                        $sr.Dispose()
                    }
                    $fs.Dispose()
                } catch {}
            }

            # Update completion status
            if ($exitCode -eq 0) {
                $progressBar.Value = 100
                $lblProgressPercent.Text = "100%"
                Set-UIExecutionState -Running $false -TaskTitle $global:activeTaskName -StatusText "Erfolgreich abgeschlossen in $elapsedSec s" -Success $true
                Add-ActivityItem -Message "[ERFOLG] $global:activeTaskName erfolgreich abgeschlossen (Dauer: $elapsedSec s)." -Type "Success"
                Write-CCLog "Task $global:activeTaskName completed successfully in $elapsedSec s"
            } else {
                Set-UIExecutionState -Running $false -TaskTitle $global:activeTaskName -StatusText "Beendet mit Hinweisen/Fehlern (Code $exitCode) nach $elapsedSec s" -Success $false
                Add-ActivityItem -Message "[HINWEIS] Vorgang beendet mit ExitCode $exitCode (Dauer: $elapsedSec s)." -Type "Warn"
                Write-CCLog "Task $global:activeTaskName finished with exit code $exitCode" "WARN"
            }

            try { $global:activeProcess.Dispose() } catch {}
            $global:activeProcess = $null

            # Clean up temp communication log
            try { Remove-Item -Path $global:activeProgressLog -Force -ErrorAction SilentlyContinue } catch {}
            $global:activeProgressLog = $null
        }
    })

    $global:pollTimer = $timer
    $timer.Start()
}

function Process-ProgressLine {
    param([string]$Line)

    # Clean date prefix for display if present
    $cleanText = $Line -replace '^\[\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\]\s*', ''

    # 1. Step detection: [Schritt X/Y] or [Step X/Y] or [Phase X/Y] or [Modul X/Y]
    if ($cleanText -match '\[(?:Schritt|Step|Phase|Modul|Module)\s+(\d+)\/(\d+)\]\s*(.*)') {
        $cur = [int]$matches[1]
        $tot = [int]$matches[2]
        $desc = $matches[3].Trim()
        $global:taskCurrentStep = $cur
        $global:taskTotalSteps = $tot
        $pct = [int][math]::Round(($cur / $tot) * 100)
        $progressBar.Value = $pct
        $lblProgressPercent.Text = "$pct%"
        $lblCurrentStep.Text = "Schritt $cur von $($tot): $desc"
        Add-ActivityItem -Message "Schritt $cur von $($tot): $desc" -Type "Action"
        return
    }

    # 2. Percentage progress detection: PROGRESS: X% - Description
    if ($cleanText -match 'PROGRESS:\s*(\d+)%\s*-\s*(.*)') {
        $pct = [int]$matches[1]
        $desc = $matches[2].Trim()
        $progressBar.Value = $pct
        $lblProgressPercent.Text = "$pct%"
        $lblCurrentStep.Text = $desc
        Add-ActivityItem -Message $desc -Type "Action"
        return
    }

    # 3. Substep arrows: -> Description
    if ($cleanText -match '^\s*->\s*(.*)') {
        $sub = $matches[1].Trim()
        $lblCurrentStep.Text = $sub
        Add-ActivityItem -Message "  ➔ $sub" -Type "Default"
        return
    }

    # 4. Status badges
    if ($cleanText -match '\[OK\]|\[SUCCESS\]|\[ERFOLG\]') {
        $msg = $cleanText -replace '^\[.*?\]\s*', ''
        Add-ActivityItem -Message "✔ $msg" -Type "Success"
        $lblCurrentStep.Text = $msg
    } elseif ($cleanText -match '\[WARN\]|\[WARNUNG\]|Notice:|Warnung:') {
        Add-ActivityItem -Message "⚠ $cleanText" -Type "Warn"
    } elseif ($cleanText -match '\[FEHLER\]|\[ERROR\]|Fehler:|Exception') {
        Add-ActivityItem -Message "✖ $cleanText" -Type "Error"
    } elseif ($cleanText -match '\[ACTION\]') {
        $msg = $cleanText -replace '^\[ACTION\]\s*', ''
        Add-ActivityItem -Message "⚙ $msg" -Type "Action"
    } elseif ($cleanText -match '\[START\]|\[DONE\]') {
        # General milestone
        $msg = $cleanText -replace '^\[.*?\]\s*', ''
        if ($msg -and -not ($msg -match '^=+')) {
            Add-ActivityItem -Message $msg -Type "Default"
        }
    }
}

function Stop-ActiveScript {
    if ($global:activeProcess -and (-not $global:activeProcess.HasExited)) {
        try {
            $global:activeProcess.Kill()
        } catch {}
    }
    if ($global:pollTimer) {
        $global:pollTimer.Stop()
        $global:pollTimer = $null
    }
    if ($global:activeProgressLog -and (Test-Path $global:activeProgressLog)) {
        try { Remove-Item -Path $global:activeProgressLog -Force -ErrorAction SilentlyContinue } catch {}
        $global:activeProgressLog = $null
    }
    Set-UIExecutionState -Running $false -TaskTitle $global:activeTaskName -StatusText "Vorgang durch Benutzer abgebrochen" -Success $false
    Add-ActivityItem -Message "[ABBRUCH] Der Vorgang wurde durch den Benutzer abgebrochen." -Type "Error"
    Write-CCLog "Task $global:activeTaskName was canceled by user" "WARN"
}

function Add-ActivityItem {
    param(
        [string]$Message,
        [string]$Type = "Default"
    )
    $border = New-Object System.Windows.Controls.Border
    $border.Padding = [System.Windows.Thickness]::new(9, 6, 9, 6)
    $border.Margin = [System.Windows.Thickness]::new(0, 2, 0, 2)
    $border.CornerRadius = [System.Windows.CornerRadius]::new(5)
    $border.BorderThickness = [System.Windows.Thickness]::new(1)

    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.FontSize = 11.5
    $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $tb.Text = $Message

    switch ($Type) {
        "Success" {
            $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ECFDF3")
            $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D1FADF")
            $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#027A48")
            $tb.FontWeight = [System.Windows.FontWeights]::SemiBold
        }
        "Action" {
            $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EFF8FF")
            $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D1E9FF")
            $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#175CD3")
            $tb.FontWeight = [System.Windows.FontWeights]::SemiBold
        }
        "Warn" {
            $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFAEB")
            $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FEDF89")
            $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#B54708")
        }
        "Error" {
            $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FEF3F2")
            $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FECDCA")
            $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#B42318")
            $tb.FontWeight = [System.Windows.FontWeights]::SemiBold
        }
        default {
            $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
            $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EAECF0")
            $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#344054")
        }
    }
    $border.Child = $tb
    $pnlActivityFeed.Children.Insert(0, $border)
    while ($pnlActivityFeed.Children.Count -gt 35) {
        $pnlActivityFeed.Children.RemoveAt($pnlActivityFeed.Children.Count - 1)
    }
}

function Set-UIExecutionState {
    param(
        [bool]$Running,
        [string]$TaskTitle = "",
        [string]$StatusText = "",
        [bool]$Success = $true
    )

    $btnOnboarding.IsEnabled = (-not $Running)
    $btnFullSync.IsEnabled = (-not $Running)
    $btnQuickSync.IsEnabled = (-not $Running)
    $btnDefaults.IsEnabled = (-not $Running)
    $btnHardening.IsEnabled = (-not $Running)
    $btnPrivacy.IsEnabled = (-not $Running)
    $btnResetUser.IsEnabled = (-not $Running)
    $btnUpdateCheck.IsEnabled = (-not $Running)
    $btnOpenTui.IsEnabled = (-not $Running)
    $btnStop.IsEnabled = $Running

    if ($TaskTitle) {
        $lblTaskTitle.Text = $TaskTitle
    }
    if ($StatusText) {
        $lblCurrentStep.Text = $StatusText
    }

    if ($Running) {
        $badgeStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F79009")
        $lblStatusBadge.Text = "Wird ausgeführt..."
        $lblStatusBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#B54708")
        $lblStatusBadge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FEF0C7")
    } elseif ($Success) {
        $badgeStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#12B76A")
        $lblStatusBadge.Text = "Bereit / Erfolgreich"
        $lblStatusBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#027A48")
        $lblStatusBadge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ECFDF3")
    } else {
        $badgeStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D92D20")
        $lblStatusBadge.Text = "Hinweis / Fehler"
        $lblStatusBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#B42318")
        $lblStatusBadge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FEE4E2")
    }
}

# 5. Fast Self-Update Engine
function Check-GuiUpdates {
    param([bool]$Manual = $false)
    $localVer = Get-LocalVersion
    $remoteVersionUrl = "https://raw.githubusercontent.com/Adrixan/CaritasLaptops-Management-Scripts/main/version.json"

    if ($Manual) {
        Add-ActivityItem -Message "Prüfe GitHub auf neue Skript-Versionen..." -Type "Action"
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $remoteMeta = Invoke-RestMethod -Uri $remoteVersionUrl -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop

        if ($remoteMeta.version -and (Test-IsNewerVersion -LocalVersion $localVer -RemoteVersion $remoteMeta.version)) {
            $lblVersionBadge.Text = "Version $localVer (Update: $($remoteMeta.version))"
            $btnApplyUpdate.Visibility = [System.Windows.Visibility]::Visible
            $btnApplyUpdate.Content = "⚡ Update auf $($remoteMeta.version)"
            $btnApplyUpdate.Tag = $remoteMeta.archiveUrl
            Add-ActivityItem -Message "[UPDATE] Neue Version $($remoteMeta.version) auf GitHub verfügbar! (Lokal: $localVer)" -Type "Action"
            Write-CCLog "Update available: local=$localVer, remote=$($remoteMeta.version)"
        } else {
            $lblVersionBadge.Text = "Version $localVer (Aktuell)"
            $btnApplyUpdate.Visibility = [System.Windows.Visibility]::Collapsed
            if ($Manual) {
                Add-ActivityItem -Message "[OK] Alle Skripte sind auf dem neuesten Stand (v$localVer)." -Type "Success"
            }
        }
    } catch {
        $lblVersionBadge.Text = "Version $localVer (Offline)"
        $btnApplyUpdate.Visibility = [System.Windows.Visibility]::Collapsed
        if ($Manual) {
            Add-ActivityItem -Message "[HINWEIS] Update-Server nicht erreichbar oder Gerät ist offline." -Type "Warn"
        }
    }
}

function Invoke-GuiSelfUpdate {
    $archiveUrl = $btnApplyUpdate.Tag
    if (-not $archiveUrl) {
        $archiveUrl = "https://github.com/Adrixan/CaritasLaptops-Management-Scripts/archive/refs/heads/main.zip"
    }

    $dialog = [System.Windows.MessageBox]::Show(
        "Möchten Sie die Verwaltungsskripte jetzt automatisch auf den neuesten Stand aktualisieren?",
        "Skript-Update durchführen",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($dialog -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Add-ActivityItem -Message "Lade Aktualisierungspaket von GitHub herunter..." -Type "Action"
    Set-UIExecutionState -Running $true -TaskTitle "Skripte aktualisieren" -StatusText "Lade Update herunter..."

    try {
        if (Test-Path $stagingDir) { Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
        $zipPath = Join-Path $stagingDir "update.zip"

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $archiveUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 30
        Expand-Archive -Path $zipPath -DestinationPath $stagingDir -Force

        $extractedRoot = Get-ChildItem -Path $stagingDir -Directory | Select-Object -First 1
        $srcScripts = if ($extractedRoot -and (Test-Path "$($extractedRoot.FullName)\scripts")) {
            "$($extractedRoot.FullName)\scripts"
        } elseif (Test-Path "$stagingDir\scripts") {
            "$stagingDir\scripts"
        } elseif ($extractedRoot) {
            $extractedRoot.FullName
        } else {
            $stagingDir
        }
        $srcVersion = if ($extractedRoot -and (Test-Path "$($extractedRoot.FullName)\version.json")) {
            "$($extractedRoot.FullName)\version.json"
        } elseif (Test-Path "$stagingDir\version.json") {
            "$stagingDir\version.json"
        } else {
            $null
        }

        $psFiles = Get-ChildItem -Path $srcScripts -Filter "*.ps1" -ErrorAction SilentlyContinue
        if ($psFiles) {
            foreach ($f in $psFiles) {
                Copy-Item -Path $f.FullName -Destination $scriptDir -Force
            }
            if ($srcVersion -and (Test-Path $srcVersion)) { Copy-Item -Path $srcVersion -Destination $localVersionFile -Force }
            $newVer = Get-LocalVersion
            Add-ActivityItem -Message "[ERFOLG] Skripte erfolgreich auf Version $newVer aktualisiert!" -Type "Success"
            Write-CCLog "Self-update applied successfully to version $newVer"
            $lblVersionBadge.Text = "Version $newVer (Aktuell)"
            $btnApplyUpdate.Visibility = [System.Windows.Visibility]::Collapsed
            [System.Windows.MessageBox]::Show(
                "Die Skripte wurden erfolgreich auf Version $newVer aktualisiert.",
                "Aktualisierung abgeschlossen",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            ) | Out-Null
        }
    } catch {
        Add-ActivityItem -Message "[FEHLER] Aktualisierung fehlgeschlagen: $_" -Type "Error"
        Write-CCLog "Self-update failed: $_" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Fehler beim Aktualisieren: $_",
            "Update-Fehler",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    } finally {
        if (Test-Path $stagingDir) { Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue }
        Set-UIExecutionState -Running $false -TaskTitle "Bereit für Aufgaben" -StatusText "Wählen Sie links eine Aktion aus, um zu beginnen."
    }
}

# 6. XAML Interface Definition (Caritas Corporate Identity & Scalable Progress Dashboard)
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Caritas Laptop Verwaltung - Kontrollzentrum"
        Height="760" Width="1180" MinHeight="620" MinWidth="960"
        WindowStartupLocation="CenterScreen"
        Background="#F2F4F7" Foreground="#1D2939"
        FontFamily="Segoe UI, Arial, sans-serif">

    <Window.Resources>
        <!-- Standard Card Panel -->
        <Style x:Key="CardPanel" TargetType="Border">
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#E4E7EC"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="14"/>
            <Setter Property="Margin" Value="0,0,0,12"/>
        </Style>

        <!-- Hero Card Panel (Caritas Red Tint) -->
        <Style x:Key="HeroCardPanel" TargetType="Border">
            <Setter Property="Background" Value="#FFF5F5"/>
            <Setter Property="BorderBrush" Value="#FECDCA"/>
            <Setter Property="BorderThickness" Value="1.5"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="16"/>
            <Setter Property="Margin" Value="0,0,0,12"/>
        </Style>

        <!-- Danger Card Panel -->
        <Style x:Key="DangerCardPanel" TargetType="Border">
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#FECDCA"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="14"/>
            <Setter Property="Margin" Value="0,0,0,12"/>
        </Style>

        <!-- Base Action Button -->
        <Style x:Key="ActionButton" TargetType="Button">
            <Setter Property="Background" Value="#1D2939"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#1D2939"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="btnBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="5">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="btnBorder" Property="Background" Value="#344054"/>
                                <Setter TargetName="btnBorder" Property="BorderBrush" Value="#344054"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="btnBorder" Property="Background" Value="#0F172A"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Hero Action Button (Caritas Red) -->
        <Style x:Key="HeroButton" TargetType="Button" BasedOn="{StaticResource ActionButton}">
            <Setter Property="Background" Value="#C41230"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#A50E28"/>
            <Setter Property="FontSize" Value="13.5"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Padding" Value="14,10"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="heroBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="5">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="heroBorder" Property="Background" Value="#9E0D25"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="heroBorder" Property="Background" Value="#780A1C"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="heroBorder" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Danger Button (Signal Red) -->
        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource ActionButton}">
            <Setter Property="Background" Value="#D92D20"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#B42318"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="dangerBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="5">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="dangerBorder" Property="Background" Value="#B42318"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="dangerBorder" Property="Background" Value="#912018"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="dangerBorder" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Utility Button (Clean Light) -->
        <Style x:Key="UtilityButton" TargetType="Button" BasedOn="{StaticResource ActionButton}">
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#D0D5DD"/>
            <Setter Property="Foreground" Value="#344054"/>
            <Setter Property="FontSize" Value="11.5"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="utilBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="5">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="utilBorder" Property="Background" Value="#F2F4F7"/>
                                <Setter TargetName="utilBorder" Property="BorderBrush" Value="#98A2B3"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="utilBorder" Property="Background" Value="#EAECF0"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="utilBorder" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- HEADER BAR (Caritas Red) -->
        <Border Grid.Row="0" Background="#C41230" CornerRadius="8" Padding="18,14" Margin="0,0,0,14">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Orientation="Vertical">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <Border Background="#FFFFFF" CornerRadius="4" Padding="7,3" Margin="0,0,12,0">
                            <TextBlock Text="CARITAS" Foreground="#C41230" FontWeight="ExtraBold" FontSize="11" FontFamily="Segoe UI Black, Arial"/>
                        </Border>
                        <TextBlock Text="LAPTOP VERWALTUNG" Foreground="#FFFFFF" FontWeight="Bold" FontSize="18" VerticalAlignment="Center"/>
                        <TextBlock Text=" | KONTROLLZENTRUM" Foreground="#FECDCA" FontSize="18" VerticalAlignment="Center"/>
                    </StackPanel>
                    <TextBlock x:Name="lblSystemInfo" Text="Host: - | System: Windows 11 | Modus: Administrator" Foreground="#FEE4E2" FontSize="12" Margin="0,4,0,0"/>
                </StackPanel>

                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock x:Name="lblVersionBadge" Text="Version 1.0.6" Foreground="#FEE4E2" FontSize="12" VerticalAlignment="Center" Margin="0,0,12,0"/>
                    <Button x:Name="btnApplyUpdate" Content="⚡ Update verfügbar" Style="{StaticResource UtilityButton}" Visibility="Collapsed" Margin="0,0,8,0"/>
                    <Button x:Name="btnUpdateCheck" Content="Updates suchen" Style="{StaticResource UtilityButton}" Margin="0,0,8,0"/>
                    <Button x:Name="btnExitApp" Content="✕ Beenden" Style="{StaticResource UtilityButton}" FontWeight="Bold"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- MAIN SPLIT AREA -->
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="420" MinWidth="360" MaxWidth="500"/>
                <ColumnDefinition Width="14"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- LEFT COLUMN: ACTION CARDS -->
            <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <StackPanel Orientation="Vertical" Margin="0,0,4,0">

                    <!-- HERO: ERST-EINRICHTUNG -->
                    <Border Style="{StaticResource HeroCardPanel}">
                        <StackPanel Orientation="Vertical">
                            <TextBlock Text="★ ERST-EINRICHTUNG (ALL-IN-ONE)" Foreground="#C41230" FontWeight="Bold" FontSize="14"/>
                            <TextBlock Text="Richtet ein gespendetes Gerät vollautomatisch schlüsselfertig ein:" Foreground="#344054" FontSize="11.5" Margin="0,4,0,0" TextWrapping="Wrap"/>
                            <TextBlock Text="• Software-Retention &amp; Winget-Apps&#x0a;• Windows Update &amp; Treiber-Synchronisation&#x0a;• System-Hardening &amp; Dauerbetrieb (kein Standby)&#x0a;• Browser-Standards (Firefox, VLC, uBlock Origin)&#x0a;• Datenschutz, USB-Sperre &amp; Gastkonto-Setup" Foreground="#475467" FontSize="11" Margin="4,4,0,10"/>
                            <Button x:Name="btnOnboarding" Content="▶ Erst-Einrichtung jetzt starten" Style="{StaticResource HeroButton}"/>
                        </StackPanel>
                    </Border>

                    <!-- SYSTEM- & SOFTWARE-WARTUNG -->
                    <Border Style="{StaticResource CardPanel}">
                        <StackPanel Orientation="Vertical">
                            <TextBlock Text="SOFTWARE- &amp; SYSTEM-WARTUNG" Foreground="#1D2939" FontWeight="Bold" FontSize="13"/>
                            <TextBlock Text="Regelmäßige Aktualisierung aller Programme und des Betriebssystems:" Foreground="#475467" FontSize="11" Margin="0,2,0,8" TextWrapping="Wrap"/>
                            <Grid Margin="0,0,0,6">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="8"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Button x:Name="btnFullSync" Grid.Column="0" Content="Vollständige Wartung" Style="{StaticResource ActionButton}" ToolTip="Winget-Apps + Windows Update + Treiber"/>
                                <Button x:Name="btnQuickSync" Grid.Column="2" Content="Schnelle Wartung" Style="{StaticResource ActionButton}" ToolTip="Nur Winget-Apps und Software-Retention"/>
                            </Grid>
                        </StackPanel>
                    </Border>

                    <!-- KONFIGURATION & RICHTLINIEN -->
                    <Border Style="{StaticResource CardPanel}">
                        <StackPanel Orientation="Vertical">
                            <TextBlock Text="STANDARDS, SICHERHEIT &amp; DATENSCHUTZ" Foreground="#1D2939" FontWeight="Bold" FontSize="13"/>
                            <TextBlock Text="Spezifische Richtlinien und App-Voreinstellungen anwenden:" Foreground="#475467" FontSize="11" Margin="0,2,0,8" TextWrapping="Wrap"/>
                            <Button x:Name="btnDefaults" Content="Standard-Programme &amp; Werbeblocker" Style="{StaticResource ActionButton}" Margin="0,0,0,6" ToolTip="Firefox, VLC, LibreOffice, MS Office &amp; uBlock Origin"/>
                            <Button x:Name="btnHardening" Content="Sicherheits- &amp; Energie-Richtlinien" Style="{StaticResource ActionButton}" Margin="0,0,0,6" ToolTip="Defender PUA, Dauerbetrieb, LLMNR/NetBIOS-Abschaltung"/>
                            <Button x:Name="btnPrivacy" Content="Datenschutz, USB-Sperre &amp; Hygiene" Style="{StaticResource ActionButton}" ToolTip="Browser-Passwörter aus, USB-Ausführung sperren, Speicherbereinigung"/>
                        </StackPanel>
                    </Border>

                    <!-- BENUTZERKONTO RESET -->
                    <Border Style="{StaticResource DangerCardPanel}">
                        <StackPanel Orientation="Vertical">
                            <TextBlock Text="BENUTZERKONTO 'USER' ZURÜCKSETZEN" Foreground="#D92D20" FontWeight="Bold" FontSize="13"/>
                            <TextBlock Text="Löscht das Profil des Gastkontos 'User' restlos und stellt den sauberen Ausgangszustand wieder her. Alle persönlichen Dateien des Gastes werden unwiderruflich entfernt." Foreground="#344054" FontSize="11" Margin="0,2,0,8" TextWrapping="Wrap"/>
                            <Button x:Name="btnResetUser" Content="Sitzung von 'User' zurücksetzen" Style="{StaticResource DangerButton}"/>
                        </StackPanel>
                    </Border>

                    <!-- UTILITY ROW -->
                    <Grid Margin="0,2,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="8"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button x:Name="btnOpenTui" Grid.Column="0" Content="Terminal (TUI)" Style="{StaticResource UtilityButton}"/>
                        <Button x:Name="btnOpenLogs" Grid.Column="2" Content="Audit-Logs Ordner" Style="{StaticResource UtilityButton}"/>
                    </Grid>

                </StackPanel>
            </ScrollViewer>

            <!-- SPLITTER / SPACER -->
            <Grid Grid.Column="1"/>

            <!-- RIGHT COLUMN: PROGRESS & STATUS MONITOR (NO RAW SHELL VIEW) -->
            <Border Grid.Column="2" Background="#FFFFFF" BorderBrush="#E4E7EC" BorderThickness="1" CornerRadius="8" Padding="18">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- ROW 0: CURRENT TASK & STATUS BANNER -->
                    <Border Grid.Row="0" Background="#F8F9FA" BorderBrush="#EAECF0" BorderThickness="1" CornerRadius="6" Padding="14" Margin="0,0,0,14">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>

                            <StackPanel Grid.Row="0" Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                                <Ellipse x:Name="badgeStatusDot" Width="12" Height="12" Fill="#12B76A" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                <TextBlock x:Name="lblTaskTitle" Text="Bereit für Aufgaben" Foreground="#1D2939" FontWeight="Bold" FontSize="15" VerticalAlignment="Center"/>
                            </StackPanel>

                            <Border Grid.Row="0" Grid.Column="1" CornerRadius="4">
                                <TextBlock x:Name="lblStatusBadge" Text="Bereit" Foreground="#027A48" Background="#ECFDF3" FontWeight="SemiBold" FontSize="12" Padding="8,3"/>
                            </Border>

                            <TextBlock x:Name="lblCurrentStep" Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="2" Text="Wählen Sie links eine Aktion aus, um zu beginnen." Foreground="#475467" FontSize="12.5" Margin="0,8,0,0" TextWrapping="Wrap"/>
                        </Grid>
                    </Border>

                    <!-- ROW 1: PROGRESS BAR & PERCENTAGE -->
                    <Border Grid.Row="1" Margin="0,0,0,16">
                        <StackPanel Orientation="Vertical">
                            <Grid Margin="0,0,0,6">
                                <TextBlock Text="Fortschritt:" Foreground="#344054" FontWeight="SemiBold" FontSize="12" HorizontalAlignment="Left"/>
                                <TextBlock x:Name="lblProgressPercent" Text="0%" Foreground="#C41230" FontWeight="Bold" FontSize="13" HorizontalAlignment="Right"/>
                            </Grid>
                            <ProgressBar x:Name="progressBar" Height="22" Minimum="0" Maximum="100" Value="0"
                                         Background="#EAECF0" Foreground="#C41230" BorderThickness="0"/>
                        </StackPanel>
                    </Border>

                    <!-- ROW 2: LIVE ACTIVITY & MILESTONE FEED -->
                    <Border Grid.Row="2" Background="#F8F9FA" BorderBrush="#EAECF0" BorderThickness="1" CornerRadius="6" Padding="12">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>

                            <TextBlock Grid.Row="0" Text="Aktivitätsverlauf &amp; Meilensteine:" Foreground="#344054" FontWeight="SemiBold" FontSize="12" Margin="0,0,0,8"/>

                            <ScrollViewer x:Name="scrollActivity" Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                                <StackPanel x:Name="pnlActivityFeed" Orientation="Vertical"/>
                            </ScrollViewer>
                        </Grid>
                    </Border>

                    <!-- ROW 3: DASHBOARD ACTION CONTROLS -->
                    <Grid Grid.Row="3" Margin="0,14,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>

                        <Button x:Name="btnStop" Grid.Column="0" Content="✕ Vorgang abbrechen" Style="{StaticResource DangerButton}" Padding="12,6" FontSize="11.5" IsEnabled="False"/>
                        <Button x:Name="btnOpenCurrentLog" Grid.Column="2" Content="Protokolldatei anzeigen" Style="{StaticResource UtilityButton}" Padding="12,6" FontSize="11.5"/>
                    </Grid>
                </Grid>
            </Border>
        </Grid>

        <!-- FOOTER BAR -->
        <Border Grid.Row="2" Margin="0,10,0,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="lblLogPath" Text="Caritas Laptop Management Suite" Foreground="#667085" FontSize="11" Grid.Column="0" VerticalAlignment="Center"/>
                <TextBlock Text="Caritas Österreich" Foreground="#667085" FontWeight="SemiBold" FontSize="11" Grid.Column="1" VerticalAlignment="Center"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# 7. Initialize GUI & Wire Event Handlers
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Resolve UI Controls
$lblSystemInfo = $window.FindName("lblSystemInfo")
$lblVersionBadge = $window.FindName("lblVersionBadge")
$btnApplyUpdate = $window.FindName("btnApplyUpdate")
$btnUpdateCheck = $window.FindName("btnUpdateCheck")
$btnExitApp = $window.FindName("btnExitApp")
$btnOnboarding = $window.FindName("btnOnboarding")
$btnFullSync = $window.FindName("btnFullSync")
$btnQuickSync = $window.FindName("btnQuickSync")
$btnDefaults = $window.FindName("btnDefaults")
$btnHardening = $window.FindName("btnHardening")
$btnPrivacy = $window.FindName("btnPrivacy")
$btnResetUser = $window.FindName("btnResetUser")
$btnOpenTui = $window.FindName("btnOpenTui")
$btnOpenLogs = $window.FindName("btnOpenLogs")
$badgeStatusDot = $window.FindName("badgeStatusDot")
$lblTaskTitle = $window.FindName("lblTaskTitle")
$lblStatusBadge = $window.FindName("lblStatusBadge")
$lblCurrentStep = $window.FindName("lblCurrentStep")
$progressBar = $window.FindName("progressBar")
$lblProgressPercent = $window.FindName("lblProgressPercent")
$pnlActivityFeed = $window.FindName("pnlActivityFeed")
$btnStop = $window.FindName("btnStop")
$btnOpenCurrentLog = $window.FindName("btnOpenCurrentLog")
$lblLogPath = $window.FindName("lblLogPath")

if ($lblLogPath) { $lblLogPath.Text = "Protokolle: $logDir" }

# Populate System Info
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
$csInfo = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
$osCaption = if ($osInfo) { $osInfo.Caption -replace "Microsoft\s+", "" } else { "Windows 11" }
$sysModel = if ($csInfo) { $csInfo.Model.Trim() } else { "Laptop" }
$lblSystemInfo.Text = "Host: $env:COMPUTERNAME ($sysModel) | System: $osCaption | Modus: Administrator"

$initialVersion = Get-LocalVersion
$lblVersionBadge.Text = "Version $initialVersion"
Add-ActivityItem -Message "Kontrollzentrum v$initialVersion bereit für Aufgaben." -Type "Default"

# Wire Action Handlers
$btnOnboarding.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "Möchten Sie die Erst-Einrichtung (All-in-One Setup) für dieses Gerät jetzt starten?`r`n`r`nDieser Vorgang umfasst:`r`n1. Software-Bereinigung & Winget-Apps`r`n2. Windows Update & Treiber`r`n3. Sicherheits-Hardening & Dauerbetrieb`r`n4. Standard-Programme & uBlock Origin`r`n5. Datenschutz & USB-Sperre`r`n6. Clean Slate Benutzerkonto-Reset & Autologon`r`n`r`nJe nach Internetverbindung kann dies mehrere Minuten dauern.",
        "Erst-Einrichtung bestätigen",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
        Start-AsyncScript -ScriptFile "$scriptDir\Caritas-ControlCenter.ps1" -Arguments "-RunOnboardingUnattended" -TaskName "Erst-Einrichtung (All-in-One)" -TargetLog "$logDir\SoftwareSync.log"
    }
})

$btnFullSync.Add_Click({
    Start-AsyncScript -ScriptFile "$scriptDir\Sync-CaritasSoftware.ps1" -Arguments "" -TaskName "Vollständige Wartung (Software & Windows Update)" -TargetLog "$logDir\SoftwareSync.log"
})

$btnQuickSync.Add_Click({
    Start-AsyncScript -ScriptFile "$scriptDir\Sync-CaritasSoftware.ps1" -Arguments "-SkipWindowsUpdate" -TaskName "Schnelle Software-Wartung" -TargetLog "$logDir\SoftwareSync.log"
})

$btnDefaults.Add_Click({
    Start-AsyncScript -ScriptFile "$scriptDir\Configure-CaritasDefaults.ps1" -Arguments "" -TaskName "Standard-Programme, uBlock & Autologon" -TargetLog "$logDir\Defaults.log"
})

$btnHardening.Add_Click({
    Start-AsyncScript -ScriptFile "$scriptDir\Configure-CaritasHardening.ps1" -Arguments "" -TaskName "Sicherheits- & Energie-Richtlinien" -TargetLog "$logDir\Hardening.log"
})

$btnPrivacy.Add_Click({
    Start-AsyncScript -ScriptFile "$scriptDir\Configure-CaritasMaintenanceAndPrivacy.ps1" -Arguments "" -TaskName "Datenschutz, USB-Sperre & Wartung" -TargetLog "$logDir\Maintenance.log"
})

$btnResetUser.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "ACHTUNG: Möchten Sie das Benutzerprofil von 'User' wirklich vollständig zurücksetzen?`r`n`r`nAlle persönlichen Dokumente, Downloads und Verläufe des Gastkontos werden unwiderruflich gelöscht!",
        "Benutzerprofil 'User' zurücksetzen",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )
    if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
        Start-AsyncScript -ScriptFile "$scriptDir\Reset-CaritasUserProfile.ps1" -Arguments "-TargetUsername 'User'" -TaskName "Benutzerkonto 'User' zurücksetzen" -TargetLog "$logDir\UserReset.log"
    }
})

$btnStop.Add_Click({
    Stop-ActiveScript
})

$btnOpenLogs.Add_Click({
    if (Test-Path $logDir) {
        Start-Process explorer.exe -ArgumentList "`"$logDir`""
    } else {
        [System.Windows.MessageBox]::Show("Log-Verzeichnis existiert noch nicht.", "Hinweis", [System.Windows.MessageBoxButton]::OK) | Out-Null
    }
})

$btnOpenCurrentLog.Add_Click({
    $targetLogPath = if ($global:activeTargetLog -and (Test-Path $global:activeTargetLog)) {
        $global:activeTargetLog
    } elseif (Test-Path "$logDir\UserReset.log") {
        "$logDir\UserReset.log"
    } else {
        "$logDir\ControlCenter.log"
    }
    if (Test-Path $targetLogPath) {
        Start-Process notepad.exe -ArgumentList "`"$targetLogPath`""
    } else {
        [System.Windows.MessageBox]::Show("Protokolldatei ($targetLogPath) existiert noch nicht.", "Hinweis", [System.Windows.MessageBoxButton]::OK) | Out-Null
    }
})

$btnOpenTui.Add_Click({
    $tuiScript = "$scriptDir\Caritas-ControlCenter.ps1"
    if (Test-Path $tuiScript) {
        Start-Process powershell.exe -ArgumentList @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tuiScript)
    } else {
        [System.Windows.MessageBox]::Show("TUI-Skript ($tuiScript) nicht gefunden.", "Fehler", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
    }
})

$btnUpdateCheck.Add_Click({
    Check-GuiUpdates -Manual $true
})

$btnApplyUpdate.Add_Click({
    Invoke-GuiSelfUpdate
})

$btnExitApp.Add_Click({
    $window.Close()
})

# Window Closing Safety
$window.Add_Closing({
    param($s, $e)
    if ($global:activeProcess -and (-not $global:activeProcess.HasExited)) {
        $confirm = [System.Windows.MessageBox]::Show(
            "Ein Verwaltungsvorgang wird gerade noch ausgeführt. Wenn Sie jetzt schließen, wird der Vorgang abgebrochen. Wirklich beenden?",
            "Vorgang aktiv",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) {
            $e.Cancel = $true
            return
        }
        Stop-ActiveScript
    }
})

# Check for updates quietly after window loads
$window.Add_Loaded({
    Check-GuiUpdates -Manual $false
})

# Display Window
$window.ShowDialog() | Out-Null
