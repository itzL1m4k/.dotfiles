# Function to refreshing env variables
function refreshenv {
  $env:Path = [System.Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::Machine) + ';' + [System.Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::User)
  $env:PSModulePath = [System.Environment]::GetEnvironmentVariable('PSModulePath', [System.EnvironmentVariableTarget]::Machine) + ';' + [System.Environment]::GetEnvironmentVariable('PSModulePath', [System.EnvironmentVariableTarget]::User)
}

# Function to create symlinks
function New-Link {
  param (
    [string]$Path,
    [string]$Target
  )
  try {
    if (-not (Test-Path $Path)) {
      New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force
    }
  }
  catch {
    Write-Error "Error creating symlink: $($_.Exception.Message)"
  }
}

# Function to install programs from links
function Install-Programs {
  param (
    [string]$tempPath,
    [string]$url,
    [string]$install
  )
  # Download the file with error handling
  try {
    Invoke-WebRequest -Uri $url -OutFile $tempPath -ErrorAction Stop
    Write-Host "Download complete: $url"
  }
  catch {
    Write-Error "Error downloading file: $($_.Exception.Message)"
    return
  }

  Start-Process -FilePath $tempPath -Wait
  Remove-Item $tempPath
}

# Install or update winget, then apply settings
Invoke-WebRequest -useb https://raw.githubusercontent.com/itzL1m4k/.dotfiles/main/installWinget.ps1 | Invoke-Expression

# Hashtable to store flags for specific applications
$flags = @{
  "Git.Git"   = "-i"
  "7zip.7zip" = "--force"
}

# List of applications to install via winget
$apps = @(
  "Microsoft.XNARedist",
  "OpenAL.OpenAL",
  "Microsoft.WindowsTerminal.Preview",
  "Microsoft.PowerShell.Preview",
  "Git.Git",
  "7zip.7zip",
  "Starship.Starship",
  "chrisant996.Clink",
  "OpenJS.NodeJS",
  "Oracle.JavaRuntimeEnvironment",
  "Notepad++.Notepad++",
  "sylikc.JPEGView",
  "VideoLAN.VLC",
  "AntibodySoftware.WizTree",
  "voidtools.Everything.Lite",
  "BleachBit.BleachBit",
  "KDE.Krita",
  "OBSProject.OBSStudio",
  "Skillbrains.Lightshot",
  "RevoUninstaller.RevoUninstaller",
  "EpicGames.EpicGamesLauncher",
  "Valve.Steam",
  "Discord.Discord"
)

# Installing the applications with the appropriate flags
foreach ($app in $apps) {
  $appFlags = $flags[$app]
  if ($appFlags) {
    winget install --id=$app -e $appFlags
  }
  else {
    winget install --id=$app -e
  }
}

# refreshing env variables
refreshenv

# Open new powershell without admin right and install spotify, then spicetify
$installSpotify = "winget install -e --id Spotify.Spotify"
$installSpicetify = "Invoke-WebRequest -useb https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.ps1 | Invoke-Expression"

runas /user:$env:USERNAME "powershell.exe -NoProfile $installSpotify ; $installSpicetify"

# Cloning the repository to the hidden directory .dotfiles
if (-not (Test-Path "$env:USERPROFILE\.dotfiles")) {
  git clone https://github.com/itzL1m4k/.dotfiles.git "$env:USERPROFILE\.dotfiles"
}

# Install vscode, vencord
Install-Programs "$env:TEMP\setup.exe" "https://go.microsoft.com/fwlink/?linkid=852157"
Install-Programs "$env:TEMP\VencordInstaller.exe" "https://github.com/Vencord/Installer/releases/latest/download/VencordInstaller.exe"

# Creating env variable for ~/.dotfiles
$env:DOTFILES = "$env:USERPROFILE\.dotfiles"

# Creating symlinks
New-Link "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json" "$env:DOTFILES\terminal\settings.json"
New-Link "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" "$env:DOTFILES\powershell\powershell.ps1"
New-Link "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" "$env:DOTFILES\powershell\powershell.ps1"
New-Link "$env:APPDATA\Notepad++\themes\Dracula.xml" "$env:DOTFILES\notepadpp\Dracula.xml"
New-Link "$env:USERPROFILE\.config\starship.toml" "$env:DOTFILES\.config\starship.toml"
New-Link "$env:LOCALAPPDATA\clink\starship.lua" "$env:DOTFILES\clink\starship.lua"
New-Link "$env:USERPROFILE\.bash_profile" "$env:DOTFILES\.bash_profile"
New-Link "$env:USERPROFILE\.gitconfig" "$env:DOTFILES\.gitconfig"

# Refreshing env variables
refreshenv