@echo off
setlocal
title Caritas Laptop Verwaltung

set SCRIPT_DIR=C:\Caritas\Scripts
set GUI_SCRIPT=%SCRIPT_DIR%\Caritas-ControlCenter-GUI.ps1
set TUI_SCRIPT=%SCRIPT_DIR%\Caritas-ControlCenter.ps1

rem Check if GUI script exists; fall back to TUI if needed
if exist "%GUI_SCRIPT%" (
    set TARGET_SCRIPT=%GUI_SCRIPT%
) else (
    set TARGET_SCRIPT=%TUI_SCRIPT%
)

rem Launch PowerShell elevated in Single-Thread Apartment mode with execution policy bypass
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process powershell.exe -ArgumentList '-Sta -NoProfile -ExecutionPolicy Bypass -File \"\"%TARGET_SCRIPT%\"\"' -Verb RunAs"

endlocal
