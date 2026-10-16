@echo off
setlocal

set "RELEASE_API=https://api.github.com/repos/hurlburtc-png/wow-forever-addons/releases/latest"
set "TEMP_ZIP=%TEMP%\CraftRoster.zip"
set "TEMP_DIR=%TEMP%\CraftRosterInstall"

echo Installing CraftRoster...

where powershell >nul 2>nul
if errorlevel 1 (
    echo PowerShell is required to install CraftRoster.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "
    $ErrorActionPreference = 'Stop'
    $release = Invoke-RestMethod -Uri '%RELEASE_API%'
    $asset = $release.assets | Where-Object { $_.name -eq 'CraftRoster.zip' } | Select-Object -First 1
    if (-not $asset) { throw 'CraftRoster.zip was not found in the latest GitHub release.' }

    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile '%TEMP_ZIP%'

    if (Test-Path '%TEMP_DIR%') { Remove-Item '%TEMP_DIR%' -Recurse -Force }
    Expand-Archive -Path '%TEMP_ZIP%' -DestinationPath '%TEMP_DIR%'

    $wowPaths = @(
        "$env:ProgramFiles(x86)\World of Warcraft\_retail_\Interface\AddOns",
        "$env:ProgramFiles\World of Warcraft\_retail_\Interface\AddOns",
        "$env:ProgramFiles(x86)\World of Warcraft\_classic_\Interface\AddOns",
        "$env:ProgramFiles\World of Warcraft\_classic_\Interface\AddOns"
    )

    $target = $wowPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $target) {
        $target = Read-Host 'Enter your WoW Interface\\AddOns folder path'
    }

    if (-not (Test-Path $target)) {
        throw "WoW AddOns folder not found: $target"
    }

    $destination = Join-Path $target 'CraftRoster'
    if (Test-Path $destination) { Remove-Item $destination -Recurse -Force }
    Copy-Item -Path (Join-Path '%TEMP_DIR%' 'CraftRoster') -Destination $destination -Recurse

    Write-Host "CraftRoster installed to: $destination"
"

if errorlevel 1 (
    echo Installation failed.
) else (
    echo Installation complete. Restart WoW or run /reload.
)

pause
