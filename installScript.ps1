# Check if the script is run as an administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Error "This script must be run as an administrator. Run PowerShell as an administrator and try again."
  exit 1
}

# Function to install programs from links
function Install-Programs {
  param (
    [Parameter(Mandatory = $true)]
    [string]$tempPath,

    [Parameter(Mandatory = $true)]
    [string]$url
  )

  try {
    Invoke-WebRequest -Uri $url -OutFile $tempPath -UseBasicParsing -ErrorAction Stop
    Write-Host "Download complete: $url"
  }
  catch {
    Write-Error "Error downloading file from URL '$url': $($_.Exception.Message)"
    return
  }

  try {
    Start-Process -FilePath $tempPath -Wait -ErrorAction Stop
    Write-Host "Installation complete: $tempPath"
  }
  catch {
    Write-Error "Error installing program: $($_.Exception.Message)"
    return
  }
  finally {
    try {
      Remove-Item -Path $tempPath -Force -ErrorAction Stop
      Write-Host "Temporary file removed: $tempPath"
    }
    catch {
      Write-Warning "Error removing temporary file: $($_.Exception.Message)"
    }
  }
}

# Function to create symlinks
function New-Link {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Target,

    [ValidateSet('Symbolic', 'Hard')]
    [string]$LinkType = 'Symbolic',

    [switch]$Force
  )

  try {
    if (-not (Test-Path $Target)) {
      Write-Error "Target path '$Target' does not exist."
      return
    }

    if ((Test-Path $Path) -and $Force) {
      Remove-Item -Path $Path -Force
      Write-Host "Existing item at '$Path' removed."
    }

    if ($LinkType -eq 'Symbolic') {
      New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force
    } elseif ($LinkType -eq 'Hard') {
      New-Item -ItemType HardLink -Path $Path -Target $Target -Force
    }
  }
  catch {
    Write-Error "Error creating link: $($_.Exception.Message)"
  }
}

# Installing bun.sh with the official sciprt install
if (!(Get-Command bun -ErrorAction SilentlyContinue) -or !(Get-Command bunx -ErrorAction SilentlyContinue)) {
  irm bun.sh/install.ps1 | iex
}

# Open new powershell without admin right and install spicetify
$installSpicetify = "iwr -useb https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.ps1 | iex"
runas /user:$env:USERNAME "powershell.exe -NoProfile $installSpicetify"

# Creating variable for ~/.dotfiles
$dotfilesPath = "$env:USERPROFILE\.dotfiles"

# Cloning the repository to the hidden directory .dotfiles
if (Test-Path -Path $dotfilesPath) {
    Remove-Item -Path $dotfilesPath -Recurse -Force
    Write-Host "Directory '$dotfilesPath' removed."
}
git clone https://github.com/itzL1m4k/.dotfiles.git $dotfilesPath

# Install vencord for discord
Install-Programs -tempPath "$env:TEMP\VencordInstaller.exe" -url "https://github.com/Vencord/Installer/releases/latest/download/VencordInstaller.exe"
Install-Programs -tempPath "$env:TEMP\VSCodeSetup-x64.exe" -url "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64"

# Creating symlinks with -Force
New-Link -Path "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json" -Target "$dotfilesPath\terminal\settings.json" -LinkType "Symbolic" -Force
New-Link -Path "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" -Target "$dotfilesPath\powershell\powershell.ps1" -LinkType "Symbolic" -Force
New-Link -Path "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" -Target "$dotfilesPath\powershell\powershell.ps1" -LinkType "Symbolic" -Force
New-Link -Path "$env:APPDATA\Notepad++\themes\catppuccin-mocha.xml" -Target "$dotfilesPath\notepad\catppuccin-mocha.xml" -LinkType "Symbolic" -Force
New-Link -Path "$env:USERPROFILE\.config\starship.toml" -Target "$dotfilesPath\.config\starship.toml" -LinkType "Symbolic" -Force
New-Link -Path "$env:LOCALAPPDATA\clink\starship.lua" -Target "$dotfilesPath\clink\starship.lua" -LinkType "Symbolic" -Force
New-Link -Path "$env:USERPROFILE\.bash_profile" -Target "$dotfilesPath\.bash_profile" -LinkType "Symbolic" -Force
New-Link -Path "$env:USERPROFILE\.gitconfig" -Target "$dotfilesPath\.gitconfig" -LinkType "Symbolic" -Force
