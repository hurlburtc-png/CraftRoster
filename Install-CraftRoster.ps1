# CraftRoster installer
# Detects WoW installs, lets user pick, downloads latest release, validates, backs up, replaces.

$ErrorActionPreference = "Stop"

function Get-WoWInstalls {
	$roots = @(
		"$env:ProgramFiles\\World of Warcraft",
		"${env:ProgramFiles(x86)}\\World of Warcraft",
		"$env:USERPROFILE\\Documents\\World of Warcraft"
	)
	$installs = @()
	foreach ($root in $roots) {
		if (Test-Path $root) {
			foreach ($flavor in @("_classic_beta_", "_classic_", "_retail_")) {
				$addons = Join-Path $root "$flavor\\Interface\\AddOns"
				if (Test-Path $addons) {
					$installs += [PSCustomObject]@{ Flavor = $flavor; AddOns = $addons }
				}
			}
		}
	}
	return $installs
}

function Main {
	$installs = Get-WoWInstalls
	if ($installs.Count -eq 0) {
		Write-Host "No WoW installations found. Enter the path to your AddOns folder:"
		$addons = Read-Host "AddOns path"
		if (-not (Test-Path $addons)) { Write-Host "Path not found. Aborting."; exit 1 }
		$target = $addons
	} else {
		Write-Host "Found WoW installations:"
		for ($i = 0; $i -lt $installs.Count; $i++) {
			Write-Host "[$($i+1)] $($installs[$i].Flavor) -> $($installs[$i].AddOns)"
		}
		Write-Host "[$($installs.Count+1)] Custom path"
		$choice = Read-Host "Select installation (1-$($installs.Count+1))"
		if ($choice -eq "$($installs.Count+1)") {
			$addons = Read-Host "AddOns path"
			if (-not (Test-Path $addons)) { Write-Host "Path not found. Aborting."; exit 1 }
			$target = $addons
		} else {
			$target = $installs[$choice-1].AddOns
		}
	}

	$zipUrl = "https://github.com/hurlburtc-png/wow-forever-addons/releases/latest/download/CraftRoster.zip"
	$temp = Join-Path $env:TEMP "CraftRoster-install"
	if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }
	New-Item -ItemType Directory -Path $temp | Out-Null

	Write-Host "Downloading latest CraftRoster.zip..."
	$zipPath = Join-Path $temp "CraftRoster.zip"
	Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

	Write-Host "Extracting..."
	$extractPath = Join-Path $temp "extract"
	Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

	$addonFolder = Get-ChildItem $extractPath -Directory | Where-Object { $_.Name -eq "CraftRoster" } | Select-Object -First 1
	if (-not $addonFolder) { Write-Host "CraftRoster folder not found in zip. Aborting."; exit 1 }
	if (-not (Test-Path (Join-Path $addonFolder.FullName "CraftRoster.toc"))) { Write-Host "CraftRoster.toc missing. Aborting."; exit 1 }

	$dest = Join-Path $target "CraftRoster"
	if (Test-Path $dest) {
		$backup = "$dest-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
		Write-Host "Backing up existing install to $backup"
		Move-Item $dest $backup
	}

	Write-Host "Installing to $dest"
	Copy-Item $addonFolder.FullName $dest -Recurse

	if (-not (Test-Path (Join-Path $dest "CraftRoster.toc"))) {
		Write-Host "Install validation failed. Restoring backup if it existed."
		if ($backup -and (Test-Path $backup)) { Move-Item $backup $dest }
		exit 1
	}

	Write-Host "CraftRoster installed successfully to $dest"
	Write-Host "Restart WoW or type /reload to load it."
}

Main
