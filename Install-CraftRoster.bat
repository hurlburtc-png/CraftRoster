@echo off
setlocal

where powershell >nul 2>nul
if errorlevel 1 (
    echo PowerShell is required to install CraftRoster.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-CraftRoster.ps1"

if errorlevel 1 (
    echo Installation failed.
) else (
    echo Installation complete.
)

pause
