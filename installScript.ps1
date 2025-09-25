[CmdletBinding()]
param(
  [switch]$Force,
  [switch]$DryRun,
  [string]$DotfilesRepo = 'https://github.com/itzL1m4k/.dotfiles.git'
)

function Install-Winget {
  if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }
  if ($DryRun) { return $true }

  try {
    # Sprawdź czy winget jest już zainstalowany
    $winget = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
    if ($winget) {
      Write-Host "Winget is already installed" -ForegroundColor Green
      return $true
    }

    # Instaluj winget jeśli nie ma
    Write-Host "Installing winget..." -ForegroundColor Yellow
    $progressPreference = 'silentlyContinue'
    Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile "$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    Add-AppxPackage "$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    
    return $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
  }
  catch {
    Write-Error "Failed to install winget: $($_.Exception.Message)"
    return $false
  }
}

function Install-WingetApps {
  param([array]$Apps)

  $failed = @()

  foreach ($app in $Apps) {
    $pkg = if ($app -is [string]) { $app } else { $app.name }

    Write-Host "Installing $pkg..." -ForegroundColor Yellow

    if ($DryRun) { 
      Write-Host "DRY RUN: Would install $pkg" -ForegroundColor Cyan
      continue 
    }

    try {
      $result = winget install --id $pkg --silent --accept-source-agreements --accept-package-agreements
      if ($LASTEXITCODE -ne 0) { 
        Write-Warning "Failed to install $pkg (exit code: $LASTEXITCODE)"
        $failed += $pkg 
      }
      else {
        Write-Host "Successfully installed $pkg" -ForegroundColor Green
      }
    }
    catch {
      Write-Warning "Exception installing $pkg : $($_.Exception.Message)"
      $failed += $pkg
    }
  }

  if ($failed.Count -gt 0) {
    Write-Warning "Failed to install: $($failed -join ', ')"
  }
}

function New-SymLink {
  param(
    [string]$Path,
    [string]$Target
  )

  if (-not (Test-Path $Target)) {
    Write-Warning "Target not found: $Target"
    return $false
  }

  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path $parent)) {
    if (-not $DryRun) {
      New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
  }

  if (Test-Path $Path) {
    if ($Force) {
      if (-not $DryRun) {
        Remove-Item -Path $Path -Force -Recurse -ErrorAction SilentlyContinue
      }
    }
    else {
      Write-Warning "File exists: $Path (use -Force to overwrite)"
      return $false
    }
  }

  if ($DryRun) { return $true }

  try {
    if ((Get-Item $Target).PSIsContainer) {
      cmd /c mklink /D "`"$Path`"" "`"$Target`"" | Out-Null
    }
    else {
      New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force | Out-Null
    }
    return $true
  }
  catch {
    Write-Warning "Failed to create link: $($_.Exception.Message)"
    return $false
  }
}

function Set-DotfilesConfiguration {
  $dotfilesPath = Join-Path $env:USERPROFILE ".dotfiles"

  if (Test-Path $dotfilesPath) {
    if (-not $DryRun) {
      Remove-Item -Path $dotfilesPath -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  if (-not $DryRun) {
    git clone --depth 1 $DotfilesRepo $dotfilesPath
    if (-not (Test-Path $dotfilesPath)) { return $false }
  }

  # Create symbolic links
  $links = @(
    @{ Path = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"; Target = "$dotfilesPath\terminal\settings.json" },
    @{ Path = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"; Target = "$dotfilesPath\powershell\powershell.ps1" },
    @{ Path = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"; Target = "$dotfilesPath\powershell\powershell.ps1" },
    @{ Path = "$env:APPDATA\Notepad++\themes\catppuccin-mocha.xml"; Target = "$dotfilesPath\notepad\catppuccin-mocha.xml" },
    @{ Path = "$env:USERPROFILE\.config\starship.toml"; Target = "$dotfilesPath\.config\starship.toml" },
    @{ Path = "$env:LOCALAPPDATA\clink\starship.lua"; Target = "$dotfilesPath\clink\starship.lua" },
    @{ Path = "$env:USERPROFILE\.bash_profile"; Target = "$dotfilesPath\.bash_profile" },
    @{ Path = "$env:USERPROFILE\.gitconfig"; Target = "$dotfilesPath\.gitconfig" }
  )

  foreach ($link in $links) {
    New-SymLink -Path $link.Path -Target $link.Target | Out-Null
  }

  # Import registry settings
  $regPath = Join-Path $dotfilesPath "registry\registry.reg"
  if ((Test-Path $regPath) -and -not $DryRun) {
    Write-Host "Importing registry settings..."
    reg import "`"$regPath`"" | Out-Null
  }

  return $true
}

function Install-AppFromUrl {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [string]$FileName
  )

  if ($DryRun) {
    Write-Host "DRY RUN: Would download and install from $Url" -ForegroundColor Cyan
    return
  }

  $TempDir = "$env:TEMP\AppInstall"
  if (-Not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir | Out-Null
  }

  if (-Not $FileName) {
    $FileName = [System.IO.Path]::GetFileName($Url)
    if (-Not $FileName) { $FileName = "installer.exe" }
  }

  $InstallerPath = Join-Path $TempDir $FileName

  Write-Host "Downloading from $Url..." -ForegroundColor Yellow
  try {
    Invoke-WebRequest -Uri $Url -OutFile $InstallerPath -UseBasicParsing
  }
  catch {
    Write-Error "Download failed: $($_.Exception.Message)"
    return
  }

  if (-Not (Test-Path $InstallerPath)) {
    Write-Error "Download failed."
    return
  }

  Write-Host "Running installer..." -ForegroundColor Yellow
  Start-Process -FilePath $InstallerPath -Wait

  Remove-Item $InstallerPath -Force
  Write-Host "Installation completed." -ForegroundColor Green
}

function Set-Wallpaper {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ImagePath
  )

  if ($DryRun) {
    Write-Host "DRY RUN: Would set wallpaper to $ImagePath" -ForegroundColor Cyan
    return
  }

  if (-not (Test-Path $ImagePath)) {
    Write-Error "File does not exist: $ImagePath"
    return
  }

  Add-Type @"
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport(""user32.dll"", SetLastError = true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

  # 20 = SPI_SETDESKWALLPAPER, 3 = SPIF_UPDATEINIFILE + SPIF_SENDCHANGE
  [Wallpaper]::SystemParametersInfo(20, 0, $ImagePath, 3)
  Write-Host "Wallpaper set to $ImagePath" -ForegroundColor Green
}

function Set-RunAsAdminTask {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,
    [Parameter(Mandatory = $true)]
    [string]$TaskName
  )

  if ($DryRun) {
    Write-Host "DRY RUN: Would create scheduled task '$TaskName' for $ScriptPath" -ForegroundColor Cyan
    return
  }

  if (-not (Test-Path $ScriptPath)) {
    Write-Error "File does not exist: $ScriptPath"
    return
  }

  # Usuń stare zadanie, jeśli istnieje
  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  }

  # Tworzenie nowego zadania
  $action = New-ScheduledTaskAction -Execute $ScriptPath
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  $principal = New-ScheduledTaskPrincipal -UserId "BUILTIN\Users" -LogonType Interactive -RunLevel Highest

  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal

  Write-Host "Task '$TaskName' created to run $ScriptPath as admin at every logon." -ForegroundColor Green
}

# ---------- Main execution ----------
Write-Host "Starting Windows setup with Winget..." -ForegroundColor Cyan

if (-not (Install-Winget)) {
  Write-Error "Winget installation failed"
  exit 1
}

# Lista aplikacji do zainstalowania przez Winget
$wingetApps = @(
  'abbodi1406.vcredist',
  '7zip.7zip',
  'Git.Git',
  'Microsoft.PowerShell',
  'Starship.Starship',
  'chrisant996.Clink',
  'Fastfetch-cli.Fastfetch',
  'Oven-sh.Bun',
  'yt-dlp.yt-dlp',
  'Gyan.FFmpeg',
  'Brave.Brave',
  'Discord.Discord',
  'Microsoft.WindowsTerminal',
  'Notepad++.Notepad++',
  'VideoLAN.VLC',
  'nomacs.nomacs',
  'OBSProject.OBSStudio',
  'qBittorrent.qBittorrent.Enhanced',
  'voidtools.Everything',
  'WizTree.WizTree',
  'BleachBit.BleachBit',
  'Krita.Krita',
  'EpicGames.EpicGamesLauncher',
  'Nvidia.GeForceNow',
  'Valve.Steam',
  'PrismLauncher.PrismLauncher',
  'RevoUninstaller.RevoUninstaller',
  'Anytype.Anytype'
)

# Fonts (osobno bo mogą wymagać specjalnego traktowania)
$fontApps = @(
  'DEVCOM.JetBrainsMonoNerdFont',
  'Microsoft.CascadiaCode'
)

Write-Host "Installing applications via Winget..." -ForegroundColor Green
Install-WingetApps -Apps $wingetApps

Write-Host "Installing fonts..." -ForegroundColor Green
Install-WingetApps -Apps $fontApps

# Aplikacje, które muszą być instalowane ręcznie
Write-Host "Installing applications that require manual download..." -ForegroundColor Green
Install-AppFromUrl -Url "https://steelseries.com/gg/downloads/gg/latest/windows" -FileName "SteelSeriesGG.exe"

# Refresh environment variables
Write-Host "Refreshing environment variables..." -ForegroundColor Yellow
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# Git configuration
if (Get-Command git -ErrorAction SilentlyContinue) {
  git config --global credential.helper manager
}

# Dotfiles configuration
Write-Host "Configuring dotfiles..." -ForegroundColor Green
if (-not (Set-DotfilesConfiguration)) {
  Write-Warning "Dotfiles configuration failed"
}

# Set wallpaper
if (Test-Path "$env:USERPROFILE\.dotfiles\wallpapers\background.jpg") {
  Set-Wallpaper -ImagePath "$env:USERPROFILE\.dotfiles\wallpapers\background.jpg"
}

# Create scheduled task
if (Test-Path "$env:USERPROFILE\.dotfiles\clear.bat") {
  Set-RunAsAdminTask -ScriptPath "$env:USERPROFILE\.dotfiles\clear.bat" -TaskName "clear-temp"
}

# Clone Neovim configuration
Write-Host "Setting up Neovim configuration..." -ForegroundColor Green
if (-not $DryRun) {
  if (Test-Path "${env:LOCALAPPDATA}\nvim") {
    Remove-Item "${env:LOCALAPPDATA}\nvim" -Recurse -Force -ErrorAction SilentlyContinue
  }
  git clone https://github.com/nvim-lua/kickstart.nvim.git "${env:LOCALAPPDATA}\nvim"
}

# Update all applications
Write-Host "Updating all applications..." -ForegroundColor Green
if (-not $DryRun) {
  winget upgrade --all --silent --accept-source-agreements --accept-package-agreements
}

Write-Host "Setup completed!" -ForegroundColor Green
Write-Host "Please restart your terminal to ensure all changes take effect." -ForegroundColor Yellow
