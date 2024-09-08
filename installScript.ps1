# Function to install programs from links
function Install-Programs {
  param (
    [string]$tempPath,
    [string]$url,
    [string]$install
  )
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

# Enable 'allowGlobalConfirmation' feature
choco feature enable -n allowGlobalConfirmation

# List of applications to install via Chocolatey with optional parameters
$chocoApps = @(
  @{name="vcredist-all"}, # Visual C++ redistributable
  @{name="directx"},
  @{name="nerd-fonts-cascadiacode"},
  @{name="nerd-fonts-FiraCode"},
  @{name="git.install"; params="/GitAndUnixToolsOnPath /WindowsTerminal /NoAutoCrlf"},
  @{name="vscode.install"; params="/NoContextMenuFiles /NoContextMenuFolders"},
  @{name="brave"},
  @{name="7zip.install"},
  @{name="microsoft-windows-terminal --pre"},
  @{name="pwsh --pre"},
  @{name="starship.install"},
  @{name="clink-maintained"},
  @{name="nodejs.install"},
  @{name="javaruntime"},
  @{name="notepad3.install"},
  @{name="vlc.install"},
  @{name="lightshot.install"},
  @{name="wiztree"},
  @{name="bleachbit.install"},
  @{name="krita"},
  @{name="obs-studio.install"},
  @{name="revo-uninstaller"},
  @{name="epicgameslauncher"},
  @{name="discord.install"},
  @{name="audacity"},
  @{name="equalizerapo"},
  @{name="nvidia-geforce-now"},
  @{name="spotify"},
  @{name="choco-cleaner"},
)

# Installing the applications using Chocolatey
foreach ($app in $chocoApps) {
  if ($app.params) {
    choco install $app.name --params $app.params
  } else {
    choco install $app.name
  }
}

# Cleaning chocolatey with choco-cleaner package
choco-cleaner

# Open new powershell without admin right and install spicetify
$installSpicetify = "iwr -useb https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.ps1 | iex"
runas /user:$env:USERNAME "powershell.exe -NoProfile $installSpicetify"

# refreshing env variables
refreshenv

# Cloning the repository to the hidden directory .dotfiles
if (-not (Test-Path "$env:USERPROFILE\.dotfiles")) {
  git clone https://github.com/itzL1m4k/.dotfiles.git "$env:USERPROFILE\.dotfiles"
}

# Install vencord for discord and steam
Install-Programs "$env:TEMP\VencordInstaller.exe" "https://github.com/Vencord/Installer/releases/latest/download/VencordInstaller.exe"
Install-Programs "$env:TEMP\VencordInstaller.exe" "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"

# Creating env variable for ~/.dotfiles
$env:DOTFILES = "$env:USERPROFILE\.dotfiles"

# Creating symlinks
New-Link "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json" "$env:DOTFILES\terminal\settings.json"
New-Link "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" "$env:DOTFILES\powershell\powershell.ps1"
New-Link "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" "$env:DOTFILES\powershell\powershell.ps1"
New-Link "$env:USERPROFILE\.config\starship.toml" "$env:DOTFILES\.config\starship.toml"
New-Link "$env:LOCALAPPDATA\clink\starship.lua" "$env:DOTFILES\clink\starship.lua"
New-Link "$env:USERPROFILE\.bash_profile" "$env:DOTFILES\.bash_profile"
New-Link "$env:USERPROFILE\.gitconfig" "$env:DOTFILES\.gitconfig"