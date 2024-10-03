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
    [string]$url,

    [Parameter(Mandatory = $true)]
    [string]$install
  )
  try {
    # Download the file
    Invoke-WebRequest -Uri $url -OutFile $tempPath -UseBasicParsing -ErrorAction Stop
    Write-Host "Download complete: $url"
  }
  catch {
    Write-Error "Error downloading file from URL '$url': $($_.Exception.Message)"
    return
  }

  try {
    # Install the program
    Start-Process -FilePath $tempPath -ArgumentList $install -Wait -ErrorAction Stop
    Write-Host "Installation complete: $tempPath"
  }
  catch {
    Write-Error "Error installing program: $($_.Exception.Message)"
    return
  }
  finally {
    # Clean up
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
    # Check if the target exists
    if (-not (Test-Path $Target)) {
      Write-Error "Target path '$Target' does not exist."
      return
    }

    # If the target path exists and Force is set, remove the existing item
    if ((Test-Path $Path) -and $Force) {
      Remove-Item -Path $Path -Force
      Write-Host "Existing item at '$Path' removed."
    }

    # Create a symbolic or hard link
    if ($LinkType -eq 'Symbolic') {
      New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force
    } elseif ($LinkType -eq 'Hard') {
      New-Item -ItemType HardLink -Path $Path -Target $Target -Force
    }

    Write-Host "Link created successfully: $Path -> $Target"
  }
  catch {
    Write-Error "Error creating link: $($_.Exception.Message)"
  }
}

$wingetApps = @(
  @{name="abbodi1406.vcredist"},
  @{name="Microsoft.DirectX"},
  @{name="Microsoft.XNARedist"},
  @{name="Fastfetch-cli.Fastfetch"},
  @{name="StartIsBack.StartIsBack"},
  @{name="Git.Git"; params="-i"},
  @{name="7zip.7zip"; params="--force"},
  @{name="Microsoft.VisualStudioCode"},
  @{name="Brave.Brave"},
  @{name="Microsoft.WindowsTerminal.Preview"},
  @{name="Microsoft.PowerShell"},
  @{name="Starship.Starship"},
  @{name="chrisant996.Clink"},
  @{name="OpenJS.NodeJS"},
  @{name="Oracle.JavaRuntimeEnvironment"},
  @{name="Oracle.JDK.23"},
  @{name="Notepad++.Notepad++"},
  @{name="VideoLAN.VLC"},
  @{name="nomacs.nomacs"},
  @{name="voidtools.Everything.Lite"},
  @{name="AntibodySoftware.WizTree"},
  @{name="BleachBit.BleachBit"},
  @{name="KDE.Krita"},
  @{name="OBSProject.OBSStudio"},
  @{name="RevoUninstaller.RevoUninstaller"},
  @{name="EpicGames.EpicGamesLauncher"},
  @{name="Discord.Discord"},
  @{name="Nvidia.GeForceNow"},
  @{name="Spotify.Spotify"},
  @{name="Valve.Steam"},
  @{name="9P8LTPGCBZXD"},

  # @{name="Google.AndroidStudio"},
  # @{name="Microsoft.VisualStudio.2022.Community"},
)

# Installing bun.sh with the official sciprt install
irm bun.sh/install.ps1 | iex

# Installing the applications using winget
foreach ($app in $wingetApps) {
  if ($app.params) {
    winget install -e --id $app.name $app.params
  } else {
    winget install -e --id $app.name
  }
}

# Enable 'allowGlobalConfirmation' feature
choco feature enable -n allowGlobalConfirmation

# List of applications to install via Chocolatey
$chocoApps = @(
  @{name="nerd-fonts-FiraCode"},
  @{name="equalizerapo"},
  @{name="choco-cleaner"},
)

# Installing the applications using Chocolatey
foreach ($app in $chocoApps) {
  choco install $app.name
}

# Cleaning chocolatey with choco-cleaner package
choco-cleaner

# Open new powershell without admin right and install spicetify
$installSpotify = "winget install -e --id Spotify.Spotify"
$installSpicetify = "iwr -useb https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.ps1 | iex"
runas /user:$env:USERNAME "powershell.exe -NoProfile $installSpotify && $installSpicetify"

# refreshing env variables
refreshenv

# Creating variable for ~/.dotfiles
$dotfilesPath = "$env:USERPROFILE\.dotfiles"

# Cloning the repository to the hidden directory .dotfiles
if (-not (Test-Path -Path $dotfilesPath)) {
    git clone https://github.com/itzL1m4k/.dotfiles.git $dotfilesPath
    Write-Host "Repository cloned to: $dotfilesPath"
} else {
    Write-Host "Directory '$dotfilesPath' already exists."
}

# Install vencord for discord and steam
Install-Programs -tempPath "$env:TEMP\VencordInstaller.exe" -url "https://github.com/Vencord/Installer/releases/latest/download/VencordInstaller.exe" -install ""

# Creating symlinks with -Force
New-Link -Path "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json" -Target "$dotfilesPath\terminal\settings.json" -LinkType "Symbolic" -Force
New-Link -Path "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" -Target "$dotfilesPath\powershell\powershell.ps1" -LinkType "Symbolic" -Force
New-Link -Path "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" -Target "$dotfilesPath\powershell\powershell.ps1" -LinkType "Symbolic" -Force
New-Link -Path "$env:USERPROFILE\.config\starship.toml" -Target "$dotfilesPath\.config\starship.toml" -LinkType "Symbolic" -Force
New-Link -Path "$env:LOCALAPPDATA\clink\starship.lua" -Target "$dotfilesPath\clink\starship.lua" -LinkType "Symbolic" -Force
New-Link -Path "$env:USERPROFILE\.bash_profile" -Target "$dotfilesPath\.bash_profile" -LinkType "Symbolic" -Force
New-Link -Path "$env:USERPROFILE\.gitconfig" -Target "$dotfilesPath\.gitconfig" -LinkType "Symbolic" -Force

# Run registry regedit
Start-Process -FilePath "reg.exe" -ArgumentList "import", "C:\Users\$env:USERNAME\.dotfiles\registry\registry.reg" -Verb RunAs