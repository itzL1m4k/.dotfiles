function InstallWinget {
  # Downloading the latest winget installer
  $installerUrl = "https://aka.ms/getwinget"
  $installerPath = "$env:TEMP\winget-installer.msixbundle"

  Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

  # Installing winget
  Add-AppxPackage -Path $installerPath -AllowUnsigned

  Write-Host "Winget has been installed."
}

function Get-LatestWingetVersion {
  # Downloading the latest winget version from GitHub
  $url = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
  $response = Invoke-RestMethod -Uri $url -Headers @{"User-Agent" = "Mozilla/5.0" }
  return $response.tag_name
}

# Checking if winget is installed
$wingetPath = (Get-Command winget -ErrorAction SilentlyContinue).Path

if (-not $wingetPath) {
  Write-Host "Winget is not installed. Installing the latest version..."
  InstallWinget
}
else {
  Write-Host "Winget is installed. Checking for updates..."
  $currentVersion = winget --version
  $latestVersion = Get-LatestWingetVersion

  if ($currentVersion -ne $latestVersion) {
    Write-Host "A newer version of winget is available. Installing the latest version..."
    InstallWinget
  }
  else {
    Write-Host "Winget is up to date."
  }
}
