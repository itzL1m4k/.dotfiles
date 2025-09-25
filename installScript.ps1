[CmdletBinding()]
param(
  [switch]$Force,
  [string]$DotfilesRepo = 'https://github.com/itzL1m4k/.dotfiles.git'
)

function Install-Winget {
  if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }

  try {
    $winget = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
    if (-not $winget) {
      Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile "$env:TEMP\winget.msixbundle"
      Add-AppxPackage "$env:TEMP\winget.msixbundle"
    }
    return $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
  }
  catch { return $false }
}

function Install-WingetApps {
  param([array]$Apps)
  foreach ($app in $Apps) {
    $id = if ($app -is [string]) { $app } else { $app.name }
    winget install --id $id --silent --accept-source-agreements --accept-package-agreements
  }
}

function New-SymLink {
  param([string]$Path,[string]$Target)

  if (-not (Test-Path $Target)) { return }
  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  if (Test-Path $Path -and $Force) { Remove-Item $Path -Force -Recurse }
  if ((Get-Item $Target).PSIsContainer) {
    cmd /c mklink /D "`"$Path`"" "`"$Target`"" | Out-Null
  } else {
    New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force | Out-Null
  }
}

function Set-DotfilesConfiguration {
  $dotfilesPath = Join-Path $env:USERPROFILE ".dotfiles"
  if (Test-Path $dotfilesPath) { Remove-Item $dotfilesPath -Recurse -Force -ErrorAction SilentlyContinue }
  git clone --depth 1 $DotfilesRepo $dotfilesPath

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

  foreach ($link in $links) { New-SymLink -Path $link.Path -Target $link.Target }

  $regPath = Join-Path $dotfilesPath "registry\registry.reg"
  if (Test-Path $regPath) { reg import "`"$regPath`"" | Out-Null }
}

function Install-AppFromUrl {
  param([string]$Url,[string]$FileName)
  $TempDir = "$env:TEMP\AppInstall"
  if (-Not (Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir | Out-Null }
  if (-Not $FileName) { $FileName = [System.IO.Path]::GetFileName($Url) }
  $InstallerPath = Join-Path $TempDir $FileName
  Invoke-WebRequest -Uri $Url -OutFile $InstallerPath
  Start-Process -FilePath $InstallerPath -Wait
  Remove-Item $InstallerPath -Force
}

function Set-Wallpaper {
  param([string]$ImagePath)
  if (-not (Test-Path $ImagePath)) { return }
  Add-Type @"
using System.Runtime.InteropServices;
public class Wallpaper {
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
  [Wallpaper]::SystemParametersInfo(20, 0, $ImagePath, 3)
}

function Set-RunAsAdminTask {
  param([string]$ScriptPath,[string]$TaskName)
  if (-not (Test-Path $ScriptPath)) { return }
  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  }
  $action = New-ScheduledTaskAction -Execute $ScriptPath
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  $principal = New-ScheduledTaskPrincipal -UserId "BUILTIN\Users" -LogonType Interactive -RunLevel Highest
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal
}

# ---------- Main ----------
if (-not (Install-Winget)) { exit 1 }

$wingetApps = @(
  'abbodi1406.vcredist','7zip.7zip','Git.Git','Microsoft.PowerShell','Starship.Starship',
  'chrisant996.Clink','Fastfetch-cli.Fastfetch','Oven-sh.Bun','yt-dlp.yt-dlp','Gyan.FFmpeg',
  'Brave.Brave','Discord.Discord','Microsoft.WindowsTerminal','Notepad++.Notepad++','VideoLAN.VLC',
  'nomacs.nomacs','OBSProject.OBSStudio','qBittorrent.qBittorrent.Enhanced','voidtools.Everything',
  'WizTree.WizTree','BleachBit.BleachBit','Krita.Krita','EpicGames.EpicGamesLauncher','Nvidia.GeForceNow',
  'Valve.Steam','PrismLauncher.PrismLauncher','RevoUninstaller.RevoUninstaller','Anytype.Anytype'
)

$fontApps = @('DEVCOM.JetBrainsMonoNerdFont','Microsoft.CascadiaCode')

Install-WingetApps -Apps $wingetApps
Install-WingetApps -Apps $fontApps
Install-AppFromUrl -Url "https://steelseries.com/gg/downloads/gg/latest/windows" -FileName "SteelSeriesGG.exe"

if (Get-Command git -ErrorAction SilentlyContinue) { git config --global credential.helper manager }

Set-DotfilesConfiguration

if (Test-Path "$env:USERPROFILE\.dotfiles\wallpapers\background.jpg") {
  Set-Wallpaper -ImagePath "$env:USERPROFILE\.dotfiles\wallpapers\background.jpg"
}

if (Test-Path "$env:USERPROFILE\.dotfiles\clear.bat") {
  Set-RunAsAdminTask -ScriptPath "$env:USERPROFILE\.dotfiles\clear.bat" -TaskName "clear-temp"
}

if (Test-Path "${env:LOCALAPPDATA}\nvim") {
  Remove-Item "${env:LOCALAPPDATA}\nvim" -Recurse -Force -ErrorAction SilentlyContinue
}
git clone https://github.com/nvim-lua/kickstart.nvim.git "${env:LOCALAPPDATA}\nvim"

winget upgrade --all --silent --accept-source-agreements --accept-package-agreements
