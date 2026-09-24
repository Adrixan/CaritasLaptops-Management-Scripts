#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Caritas Laptop Control Center - Graphical User Interface (GUI).
.DESCRIPTION
    Native Windows Presentation Framework (WPF) administrative console for Caritas laptops:
    - Tech-wear professional dark theme ("Bioluminescent Night" palette).
    - Asynchronous process execution with real-time output log streaming.
    - Zero external runtimes: 100% native .NET WPF and PowerShell 5.1/7+.
    - 1-Click Master Onboarding routine for newly donated laptops.
    - Modular maintenance actions (Software retention, Windows Update, Hardening, App Defaults).
    - Session reset routine for the patron account 'User'.
    - Fast-fail GitHub update checking with 1-click self-updating.
    - Bidirectional handoff to the Terminal User Interface (TUI).
.NOTES
    Compatible with all Windows 11 editions (Home, Pro, Enterprise, Education).
    Logs operations to logs\ControlCenter.log.
#>
[CmdletBinding()]
param()

# Enforce UTF-8 console and pipeline encoding
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# 1. Enforce STA (Single-Thread Apartment) Mode
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    Start-Process powershell.exe -ArgumentList @('-Sta', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    exit
}

# 2. Enforce Elevated Privileges (Administrator)
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @('-Sta', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    exit
}

# 3. Environment & Directories (Dynamically Resolved)
$ErrorActionPreference = "Continue"

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Item -Path ".").FullName }

$baseDir = Split-Path -Path $scriptDir -Parent
if (-not (Test-Path "$baseDir\scripts")) {
    $baseDir = $scriptDir
}

$configDir = Join-Path $baseDir "config"
$logDir = Join-Path $baseDir "logs"
$stagingDir = Join-Path $env:TEMP "CaritasStaging"

foreach ($dir in @($scriptDir, $configDir, $logDir)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

$localVersionFile = Join-Path $baseDir "version.json"
if (-not (Test-Path $localVersionFile)) {
    $localVersionFile = Join-Path $configDir "version.json"
}
$logFile = Join-Path $logDir "ControlCenter.log"

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

function Write-CCLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Get-LocalVersion {
    if (Test-Path $localVersionFile) {
        try {
            $v = Get-Content $localVersionFile -Raw | ConvertFrom-Json
            if ($v.version) { return $v.version }
        } catch {}
    }
    return "1.0.0"
}

# 4. Asynchronous Task Execution Engine
$global:activeProcess = $null
$global:activeRunspace = $null
$global:activeSyncState = $null
$global:pollTimer = $null

function Start-AsyncScript {
    param(
        [string]$ScriptFile,
        [string]$Arguments = "",
        [string]$TaskName = "Vorgang"
    )

    if ($global:activeSyncState -and (-not $global:activeSyncState.Done)) {
        [System.Windows.MessageBox]::Show(
            "Ein anderer Vorgang wird derzeit noch ausgeführt. Bitte warten Sie, bis dieser abgeschlossen ist.",
            "Vorgang aktiv",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        ) | Out-Null
        return
    }

    Set-UIExecutionState -Running $true -StatusText "Wird ausgeführt: $TaskName..."
    Append-LogLine "`r`n======================================================================`r`n[START] $TaskName - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n======================================================================"
    Write-CCLog "GUI launched task: $TaskName ($ScriptFile $Arguments)"

    $syncState = [hashtable]::Synchronized(@{
        Queue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        Done = $false
        ExitCode = 0
        ProcessId = 0
        Cancelled = $false
    })
    $global:activeSyncState = $syncState

    $runspace = [powershell]::Create()
    $null = $runspace.AddScript({
        param($sync, $sFile, $sArgs)
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}; `$OutputEncoding = [System.Text.Encoding]::UTF8; & { & '$sFile' $sArgs } *>&1 | ForEach-Object { [Console]::WriteLine(`$_.ToString()) }`""
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.RedirectStandardOutput = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        try {
            $proc = [System.Diagnostics.Process]::Start($psi)
            $sync.ProcessId = $proc.Id

            $action = {
                param($sender, $e)
                if ($e.Data -ne $null) {
                    $sync.Queue.Enqueue($e.Data)
                }
            }
            $proc.EnableRaisingEvents = $true
            $reg = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $action
            $proc.BeginOutputReadLine()

            while (-not $proc.WaitForExit(250)) {
                if ($sync.Cancelled) {
                    try { $proc.Kill() } catch {}
                    break
                }
            }

            try { $proc.CancelOutputRead() } catch {}
            try { Unregister-Event -SourceIdentifier $reg.Name -ErrorAction SilentlyContinue } catch {}

            $sync.ExitCode = $proc.ExitCode
        } catch {
            $sync.Queue.Enqueue("[FEHLER] Prozessausführung fehlgeschlagen: $_")
            $sync.ExitCode = 1
        } finally {
            $sync.Done = $true
        }
    }).AddArgument($syncState).AddArgument($ScriptFile).AddArgument($Arguments)

    $global:activeRunspace = $runspace
    $null = $runspace.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(50)
    $timer.Add_Tick({
        $line = $null
        while ($syncState.Queue.TryDequeue([ref]$line)) {
            Append-LogLine $line
        }

        if ($syncState.Done) {
            $timer.Stop()
            $global:pollTimer = $null
            $global:activeProcess = $null

            if ($syncState.ProcessId -gt 0) {
                try {
                    $p = [System.Diagnostics.Process]::GetProcessById($syncState.ProcessId)
                    $p.Dispose()
                } catch {}
            }

            if ($global:activeRunspace) {
                try { $global:activeRunspace.Dispose() } catch {}
                $global:activeRunspace = $null
            }

            $duration = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            if ($syncState.ExitCode -eq 0) {
                Append-LogLine "`r`n[ERFOLG] $TaskName erfolgreich abgeschlossen (Code 0) um $duration.`r`n"
                Set-UIExecutionState -Running $false -StatusText "Bereit - $TaskName erfolgreich abgeschlossen" -Success $true
                Write-CCLog "Task $TaskName finished successfully (ExitCode 0)"
            } else {
                Append-LogLine "`r`n[WARNUNG/FEHLER] $TaskName beendet mit Code $($syncState.ExitCode) um $duration.`r`n"
                Set-UIExecutionState -Running $false -StatusText "Abgeschlossen mit Hinweisen/Fehlern (Code $($syncState.ExitCode))" -Success $false
                Write-CCLog "Task $TaskName finished with ExitCode $($syncState.ExitCode)" "WARN"
            }
        }
    })

    $global:pollTimer = $timer
    $timer.Start()
}

function Stop-ActiveScript {
    if ($global:activeSyncState) {
        $global:activeSyncState.Cancelled = $true
        if ($global:activeSyncState.ProcessId -gt 0) {
            try {
                $p = [System.Diagnostics.Process]::GetProcessById($global:activeSyncState.ProcessId)
                if (-not $p.HasExited) {
                    $p.Kill()
                }
            } catch {}
        }
    }
    if ($global:activeRunspace) {
        Append-LogLine "`r`n[ABBRUCH] Abbruch durch Benutzer angefordert...`r`n"
        Write-CCLog "Task canceled by user" "WARN"
        try {
            $global:activeRunspace.Stop()
            $global:activeRunspace.Dispose()
        } catch {}
        $global:activeRunspace = $null
    }
    if ($global:pollTimer) {
        $global:pollTimer.Stop()
        $global:pollTimer = $null
    }
    Set-UIExecutionState -Running $false -StatusText "Vorgang abgebrochen" -Success $false
}

function Append-LogLine {
    param([string]$Text)
    $txtConsole.AppendText($Text + [Environment]::NewLine)
    $txtConsole.ScrollToEnd()
}

function Set-UIExecutionState {
    param(
        [bool]$Running,
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

    $progressBar.IsIndeterminate = $Running
    $progressBar.Visibility = if ($Running) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Hidden }

    if ($StatusText) {
        $lblStatus.Text = $StatusText
    }

    if ($Running) {
        $badgeStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B")
    } elseif ($Success) {
        $badgeStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
    } else {
        $badgeStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
    }
}

# 5. Fast Self-Update Engine
function Check-GuiUpdates {
    param([bool]$Manual = $false)
    $localVer = Get-LocalVersion
    $remoteVersionUrl = "https://raw.githubusercontent.com/Adrixan/CaritasLaptops-Management-Scripts/main/version.json"

    if ($Manual) {
        Append-LogLine "[UPDATE] Prüfe GitHub auf neue Skript-Versionen..."
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $remoteMeta = Invoke-RestMethod -Uri $remoteVersionUrl -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop

        if ($remoteMeta.version -and ($remoteMeta.version -ne $localVer)) {
            $lblVersionBadge.Text = "Version $localVer (Update verfügbar: $($remoteMeta.version))"
            $btnApplyUpdate.Visibility = [System.Windows.Visibility]::Visible
            $btnApplyUpdate.Content = "⚡ Update auf $($remoteMeta.version) installieren"
            $btnApplyUpdate.Tag = $remoteMeta.archiveUrl
            Append-LogLine "[UPDATE HINWEIS] Neue Version $($remoteMeta.version) verfügbar! (Lokal installiert: $localVer)"
            Write-CCLog "Update available: local=$localVer, remote=$($remoteMeta.version)"
        } else {
            $lblVersionBadge.Text = "Version $localVer (Aktuell)"
            $btnApplyUpdate.Visibility = [System.Windows.Visibility]::Collapsed
            if ($Manual) {
                Append-LogLine "[OK] Alle Verwaltungsskripte sind auf dem neuesten Stand (v$localVer)."
            }
        }
    } catch {
        $lblVersionBadge.Text = "Version $localVer (Offline / Server nicht erreichbar)"
        $btnApplyUpdate.Visibility = [System.Windows.Visibility]::Collapsed
        if ($Manual) {
            Append-LogLine "[HINWEIS] Update-Server nicht erreichbar oder Gerät ist offline."
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

    Append-LogLine "`r`n[UPDATE] Lade Aktualisierungspaket von GitHub herunter..."
    Set-UIExecutionState -Running $true -StatusText "Aktualisiere Skripte..."

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
            Append-LogLine "[ERFOLG] Skripte wurden erfolgreich auf Version $newVer aktualisiert!`r`n"
            Write-CCLog "Self-update applied successfully to version $newVer"
            $lblVersionBadge.Text = "Version $newVer (Aktuell)"
            $btnApplyUpdate.Visibility = [System.Windows.Visibility]::Collapsed
            [System.Windows.MessageBox]::Show(
                "Die Skripte wurden erfolgreich auf Version $newVer aktualisiert.",
                "Update abgeschlossen",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            ) | Out-Null
        }
    } catch {
        Append-LogLine "[FEHLER] Fehler bei der Aktualisierung: $_"
        Write-CCLog "Self-update failed: $_" "ERROR"
    } finally {
        if (Test-Path $stagingDir) { Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue }
        Set-UIExecutionState -Running $false -StatusText "Bereit"
    }
}

# 6. XAML Interface Definition (Tech-wear Dark Palette)
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Caritas Laptop Verwaltung - Kontrollzentrum"
        Height="780" Width="1180" MinHeight="680" MinWidth="1000"
        WindowStartupLocation="CenterScreen"
        Background="#121212" Foreground="#E0E0E0"
        FontFamily="Segoe UI, Arial, sans-serif">

    <Window.Resources>
        <!-- Standard Card Style -->
        <Style x:Key="CardPanel" TargetType="Border">
            <Setter Property="Background" Value="#1E1E1E"/>
            <Setter Property="BorderBrush" Value="#2D2D2D"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="6"/>
            <Setter Property="Padding" Value="14"/>
            <Setter Property="Margin" Value="0,0,0,12"/>
        </Style>

        <!-- Hero Card Style (Green accent) -->
        <Style x:Key="HeroCardPanel" TargetType="Border">
            <Setter Property="Background" Value="#152419"/>
            <Setter Property="BorderBrush" Value="#2E5C38"/>
            <Setter Property="BorderThickness" Value="1.5"/>
            <Setter Property="CornerRadius" Value="6"/>
            <Setter Property="Padding" Value="16"/>
            <Setter Property="Margin" Value="0,0,0,12"/>
        </Style>

        <!-- Danger Card Style (Red accent) -->
        <Style x:Key="DangerCardPanel" TargetType="Border">
            <Setter Property="Background" Value="#231717"/>
            <Setter Property="BorderBrush" Value="#5C2E2E"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="6"/>
            <Setter Property="Padding" Value="14"/>
            <Setter Property="Margin" Value="0,0,0,12"/>
        </Style>

        <!-- Base Action Button -->
        <Style x:Key="ActionButton" TargetType="Button">
            <Setter Property="Background" Value="#27272A"/>
            <Setter Property="Foreground" Value="#F4F4F5"/>
            <Setter Property="BorderBrush" Value="#3F3F46"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,7"/>
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
                                CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="btnBorder" Property="Background" Value="#3F3F46"/>
                                <Setter TargetName="btnBorder" Property="BorderBrush" Value="#71717A"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="btnBorder" Property="Background" Value="#52525B"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Primary Hero Button (Digital Fern) -->
        <Style x:Key="HeroButton" TargetType="Button" BasedOn="{StaticResource ActionButton}">
            <Setter Property="Background" Value="#4ADE80"/>
            <Setter Property="Foreground" Value="#0A2513"/>
            <Setter Property="BorderBrush" Value="#22C55E"/>
            <Setter Property="FontSize" Value="13.5"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Padding" Value="14,9"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="heroBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="heroBorder" Property="Background" Value="#86EFAC"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="heroBorder" Property="Background" Value="#22C55E"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="heroBorder" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Danger Button (Crimson) -->
        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource ActionButton}">
            <Setter Property="Background" Value="#EF4444"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#DC2626"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="dangerBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="dangerBorder" Property="Background" Value="#F87171"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="dangerBorder" Property="Background" Value="#B91C1C"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="dangerBorder" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Subtle Utility Button -->
        <Style x:Key="UtilityButton" TargetType="Button" BasedOn="{StaticResource ActionButton}">
            <Setter Property="Background" Value="#18181B"/>
            <Setter Property="BorderBrush" Value="#27272A"/>
            <Setter Property="Foreground" Value="#A1A1AA"/>
            <Setter Property="FontSize" Value="11.5"/>
            <Setter Property="Padding" Value="8,5"/>
        </Style>
    </Window.Resources>

    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- HEADER BAR -->
        <Border Grid.Row="0" Background="#18181B" BorderBrush="#27272A" BorderThickness="1" CornerRadius="6" Padding="16,12" Margin="0,0,0,14">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Orientation="Vertical">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <Border Background="#4ADE80" CornerRadius="3" Padding="6,2" Margin="0,0,10,0">
                            <TextBlock Text="CARITAS" Foreground="#0A2513" FontWeight="ExtraBold" FontSize="11" FontFamily="Segoe UI Black, Arial"/>
                        </Border>
                        <TextBlock Text="LAPTOP VERWALTUNG" Foreground="#FFFFFF" FontWeight="Bold" FontSize="18" VerticalAlignment="Center"/>
                        <TextBlock Text=" | KONTROLLZENTRUM" Foreground="#A1A1AA" FontSize="18" VerticalAlignment="Center"/>
                    </StackPanel>
                    <TextBlock x:Name="lblSystemInfo" Text="Host: - | Edition: Windows 11 | Modus: Administrator" Foreground="#71717A" FontSize="12" Margin="0,4,0,0"/>
                </StackPanel>

                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock x:Name="lblVersionBadge" Text="Version 1.0.0" Foreground="#A1A1AA" FontSize="12" VerticalAlignment="Center" Margin="0,0,12,0"/>
                    <Button x:Name="btnApplyUpdate" Content="⚡ Update verfügbar" Style="{StaticResource HeroButton}" Visibility="Collapsed" Margin="0,0,8,0"/>
                    <Button x:Name="btnUpdateCheck" Content="Updates suchen" Style="{StaticResource UtilityButton}"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- MAIN SPLIT AREA -->
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="480"/>
                <ColumnDefinition Width="14"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- LEFT COLUMN: ACTION CARDS -->
            <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <StackPanel Orientation="Vertical" Margin="0,0,4,0">

                    <!-- HERO: ERST-EINRICHTUNG -->
                    <Border Style="{StaticResource HeroCardPanel}">
                        <StackPanel Orientation="Vertical">
                            <TextBlock Text="★ ERST-EINRICHTUNG (ALL-IN-ONE)" Foreground="#4ADE80" FontWeight="Bold" FontSize="14"/>
                            <TextBlock Text="Richtet ein gespendetes Gerät vollautomatisch schlüsselfertig ein:" Foreground="#D1D5DB" FontSize="11.5" Margin="0,4,0,0" TextWrapping="Wrap"/>
                            <TextBlock Text="• Software-Retention &amp; Winget-Apps&#x0a;• Windows Update &amp; Treiber-Synchronisation&#x0a;• System-Hardening &amp; Dauerbetrieb (kein Standby)&#x0a;• Browser-Standards (Firefox, VLC, uBlock Origin)&#x0a;• Datenschutz, USB-Sperre &amp; Gastkonto-Setup" Foreground="#9CA3AF" FontSize="11" Margin="4,4,0,10"/>
                            <Button x:Name="btnOnboarding" Content="▶ Erst-Einrichtung jetzt starten" Style="{StaticResource HeroButton}"/>
                        </StackPanel>
                    </Border>

                    <!-- SYSTEM- & SOFTWARE-WARTUNG -->
                    <Border Style="{StaticResource CardPanel}">
                        <StackPanel Orientation="Vertical">
                            <TextBlock Text="SOFTWARE- &amp; SYSTEM-WARTUNG" Foreground="#F4F4F5" FontWeight="Bold" FontSize="13"/>
                            <TextBlock Text="Regelmäßige Aktualisierung aller Programme und des Betriebssystems:" Foreground="#9CA3AF" FontSize="11" Margin="0,2,0,8" TextWrapping="Wrap"/>
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
                            <TextBlock Text="STANDARDS, SICHERHEIT &amp; DATENSCHUTZ" Foreground="#F4F4F5" FontWeight="Bold" FontSize="13"/>
                            <TextBlock Text="Spezifische Richtlinien und App-Voreinstellungen anwenden:" Foreground="#9CA3AF" FontSize="11" Margin="0,2,0,8" TextWrapping="Wrap"/>
                            <Button x:Name="btnDefaults" Content="Standard-Programme &amp; Werbeblocker" Style="{StaticResource ActionButton}" Margin="0,0,0,6" ToolTip="Firefox, VLC, LibreOffice, MS Office &amp; uBlock Origin"/>
                            <Button x:Name="btnHardening" Content="Sicherheits- &amp; Energie-Richtlinien" Style="{StaticResource ActionButton}" Margin="0,0,0,6" ToolTip="Defender PUA, Dauerbetrieb, LLMNR/NetBIOS-Abschaltung"/>
                            <Button x:Name="btnPrivacy" Content="Datenschutz, USB-Sperre &amp; Hygiene" Style="{StaticResource ActionButton}" ToolTip="Browser-Passwörter aus, USB-Ausführung sperren, Speicherbereinigung"/>
                        </StackPanel>
                    </Border>

                    <!-- BENUTZERKONTO RESET -->
                    <Border Style="{StaticResource DangerCardPanel}">
                        <StackPanel Orientation="Vertical">
                            <TextBlock Text="BENUTZERKONTO 'USER' ZURÜCKSETZEN" Foreground="#F87171" FontWeight="Bold" FontSize="13"/>
                            <TextBlock Text="Löscht das Profil des Gastkontos 'User' restlos und stellt den sauberen Ausgangszustand wieder her. Alle persönlichen Dateien des Gastes werden unwiderruflich entfernt." Foreground="#D1D5DB" FontSize="11" Margin="0,2,0,8" TextWrapping="Wrap"/>
                            <Button x:Name="btnResetUser" Content="Sitzung von 'User' zurücksetzen" Style="{StaticResource DangerButton}"/>
                        </StackPanel>
                    </Border>

                    <!-- UTILITY ROW -->
                    <Grid Margin="0,2,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="8"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="8"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button x:Name="btnOpenTui" Grid.Column="0" Content="Terminal (TUI)" Style="{StaticResource UtilityButton}"/>
                        <Button x:Name="btnOpenLogs" Grid.Column="2" Content="Audit-Logs" Style="{StaticResource UtilityButton}"/>
                        <Button x:Name="btnClearLog" Grid.Column="4" Content="Ausgabe leeren" Style="{StaticResource UtilityButton}"/>
                    </Grid>

                </StackPanel>
            </ScrollViewer>

            <!-- SPLITTER / SPACER -->
            <Grid Grid.Column="1"/>

            <!-- RIGHT COLUMN: LIVE TERMINAL CONSOLE -->
            <Border Grid.Column="2" Background="#18181B" BorderBrush="#27272A" BorderThickness="1" CornerRadius="6" Padding="14">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- STATUS BAR ABOVE CONSOLE -->
                    <Grid Grid.Row="0" Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>

                        <Ellipse x:Name="badgeStatusDot" Grid.Column="0" Width="10" Height="10" Fill="#4ADE80" VerticalAlignment="Center" Margin="0,0,8,0"/>
                        <TextBlock x:Name="lblStatus" Grid.Column="1" Text="Bereit" Foreground="#E0E0E0" FontWeight="SemiBold" FontSize="12.5" VerticalAlignment="Center"/>

                        <StackPanel Grid.Column="2" Orientation="Horizontal">
                            <Button x:Name="btnStop" Content="✕ Abbrechen" Style="{StaticResource DangerButton}" Padding="8,4" FontSize="11" IsEnabled="False"/>
                        </StackPanel>
                    </Grid>

                    <!-- CONSOLE TEXTBOX -->
                    <Border Grid.Row="1" Background="#0A0A0A" BorderBrush="#27272A" BorderThickness="1" CornerRadius="4">
                        <TextBox x:Name="txtConsole" Background="Transparent" Foreground="#E0E0E0"
                                 BorderThickness="0" FontFamily="Consolas, Lucida Console, Courier New, monospace"
                                 FontSize="11.5" IsReadOnly="True" TextWrapping="Wrap"
                                 VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                                 Padding="10" SelectionBrush="#4ADE80"/>
                    </Border>

                    <!-- PROGRESS BAR BELOW CONSOLE -->
                    <ProgressBar x:Name="progressBar" Grid.Row="2" Height="4" Margin="0,8,0,0"
                                 Background="#27272A" Foreground="#4ADE80" BorderThickness="0"
                                 IsIndeterminate="False" Visibility="Hidden"/>
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
                <TextBlock x:Name="lblLogPath" Text="Protokollierung aktiv in Logs\ControlCenter.log" Foreground="#52525B" FontSize="11" Grid.Column="0" VerticalAlignment="Center"/>
                <TextBlock Text="Caritas Laptop Management Suite" Foreground="#52525B" FontSize="11" Grid.Column="1" VerticalAlignment="Center"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# 7. Initialize GUI & Wire Event Handlers
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Resolve Named UI Controls
$lblSystemInfo = $window.FindName("lblSystemInfo")
$lblVersionBadge = $window.FindName("lblVersionBadge")
$btnApplyUpdate = $window.FindName("btnApplyUpdate")
$btnUpdateCheck = $window.FindName("btnUpdateCheck")
$btnOnboarding = $window.FindName("btnOnboarding")
$btnFullSync = $window.FindName("btnFullSync")
$btnQuickSync = $window.FindName("btnQuickSync")
$btnDefaults = $window.FindName("btnDefaults")
$btnHardening = $window.FindName("btnHardening")
$btnPrivacy = $window.FindName("btnPrivacy")
$btnResetUser = $window.FindName("btnResetUser")
$btnOpenTui = $window.FindName("btnOpenTui")
$btnOpenLogs = $window.FindName("btnOpenLogs")
$btnClearLog = $window.FindName("btnClearLog")
$badgeStatusDot = $window.FindName("badgeStatusDot")
$lblStatus = $window.FindName("lblStatus")
$btnStop = $window.FindName("btnStop")
$txtConsole = $window.FindName("txtConsole")
$progressBar = $window.FindName("progressBar")
$lblLogPath = $window.FindName("lblLogPath")
if ($lblLogPath) { $lblLogPath.Text = "Protokollierung aktiv in $logFile" }

# Populate System Info
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
$csInfo = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
$osCaption = if ($osInfo) { $osInfo.Caption -replace "Microsoft\s+", "" } else { "Windows 11" }
$sysModel = if ($csInfo) { $csInfo.Model.Trim() } else { "Laptop" }
$lblSystemInfo.Text = "Host: $env:COMPUTERNAME ($sysModel) | System: $osCaption | Modus: Administrator"

# Set Initial Banner in Output
$initialVersion = Get-LocalVersion
Append-LogLine "======================================================================"
Append-LogLine " CARITAS LAPTOP KONTROLLZENTRUM - v$initialVersion"
Append-LogLine " Host: $env:COMPUTERNAME | Modell: $sysModel | Windows: $osCaption"
Append-LogLine " Bereit für Wartungs- und Administrationsaufgaben."
Append-LogLine "======================================================================"

# Wire Action Handlers
$btnOnboarding.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "Möchten Sie die Erst-Einrichtung (All-in-One Setup) für dieses Gerät jetzt starten?`r`n`r`nDieser Vorgang umfasst:`r`n1. Software-Bereinigung & Winget-Apps`r`n2. Windows Update & Treiber`r`n3. Sicherheits-Hardening & Dauerbetrieb`r`n4. Standard-Programme & uBlock Origin`r`n5. Datenschutz & USB-Sperre`r`n6. Clean Slate Benutzerkonto-Reset`r`n`r`nJe nach Internetverbindung kann dies mehrere Minuten dauern.",
        "Erst-Einrichtung bestätigen",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
        Start-AsyncScript -ScriptFile "$scriptDir\Caritas-ControlCenter.ps1" -Arguments "-RunOnboardingUnattended" -TaskName "Erst-Einrichtung (All-in-One)"
    }
})

$btnFullSync.Add_Click({
    Start-AsyncScript -ScriptFile "$scriptDir\Sync-CaritasSoftware.ps1" -Arguments "" -TaskName "Vollständige Wartung (Software & Windows Update)"
})

$btnQuickSync.Add_Click({
    Start-AsyncScript -ScriptFile "$scriptDir\Sync-CaritasSoftware.ps1" -Arguments "-SkipWindowsUpdate" -TaskName "Schnelle Software-Wartung"
})

$btnDefaults.Add_Click({
    Start-AsyncScript -ScriptFile "$scriptDir\Configure-CaritasDefaults.ps1" -Arguments "" -TaskName "Standard-Programme & uBlock Origin"
})

$btnHardening.Add_Click({
    Start-AsyncScript -ScriptFile "$scriptDir\Configure-CaritasHardening.ps1" -Arguments "" -TaskName "Sicherheits- & Energie-Richtlinien"
})

$btnPrivacy.Add_Click({
    Start-AsyncScript -ScriptFile "$scriptDir\Configure-CaritasMaintenanceAndPrivacy.ps1" -Arguments "" -TaskName "Datenschutz, USB-Sperre & Wartung"
})

$btnResetUser.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "ACHTUNG: Möchten Sie das Benutzerprofil von 'User' wirklich vollständig zurücksetzen?`r`n`r`nAlle persönlichen Dokumente, Downloads und Verläufe des Gastkontos werden unwiderruflich gelöscht!",
        "Benutzerprofil 'User' zurücksetzen",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )
    if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
        Start-AsyncScript -ScriptFile "$scriptDir\Reset-CaritasUserProfile.ps1" -Arguments "-TargetUsername 'User'" -TaskName "Benutzerkonto 'User' zurücksetzen"
    }
})

$btnStop.Add_Click({
    Stop-ActiveScript
})

$btnClearLog.Add_Click({
    $txtConsole.Clear()
    Append-LogLine "Ausgabe geleert. Bereit für nächste Aufgabe."
})

$btnOpenLogs.Add_Click({
    if (Test-Path $logDir) {
        Start-Process explorer.exe -ArgumentList $logDir
    } else {
        [System.Windows.MessageBox]::Show("Log-Verzeichnis existiert noch nicht.", "Hinweis", [System.Windows.MessageBoxButton]::OK) | Out-Null
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

# Window Closing Safety
$window.Add_Closing({
    param($s, $e)
    if ($global:activeRunspace) {
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
