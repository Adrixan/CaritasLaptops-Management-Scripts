@echo off
setlocal
title Caritas Laptop Verwaltung - Terminal-Modus

set BASE_DIR=%~dp0
if exist "%BASE_DIR%scripts\Caritas-ControlCenter.ps1" (
    set SCRIPT_DIR=%BASE_DIR%scripts
) else if exist "%BASE_DIR%..\scripts\Caritas-ControlCenter.ps1" (
    set SCRIPT_DIR=%BASE_DIR%..\scripts
) else if exist "%BASE_DIR%Caritas-ControlCenter.ps1" (
    set SCRIPT_DIR=%BASE_DIR%
) else (
    set SCRIPT_DIR=%BASE_DIR%
)

set TUI_SCRIPT=%SCRIPT_DIR%\Caritas-ControlCenter.ps1

rem Launch PowerShell elevated in interactive console with execution policy bypass
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process powershell.exe -ArgumentList '-NoExit -NoProfile -ExecutionPolicy Bypass -File \"\"%TUI_SCRIPT%\"\"' -Verb RunAs"

endlocal
