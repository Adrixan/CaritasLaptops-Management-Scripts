@echo off
setlocal
title Caritas Laptop Verwaltung - Terminal-Modus

set SCRIPT_DIR=C:\Caritas\Scripts
set TUI_SCRIPT=%SCRIPT_DIR%\Caritas-ControlCenter.ps1

rem Launch PowerShell elevated in interactive console with execution policy bypass
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process powershell.exe -ArgumentList '-NoExit -NoProfile -ExecutionPolicy Bypass -File \"\"%TUI_SCRIPT%\"\"' -Verb RunAs"

endlocal
