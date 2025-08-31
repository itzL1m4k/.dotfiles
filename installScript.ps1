[CmdletBinding()]
param(
  [switch]$Force,
  [switch]$DryRun,
  [string]$DotfilesRepo = 'https://github.com/itzL1m4k/.dotfiles.git'
)

function Install-Scoop {
  if (Get-Command scoop -ErrorAction SilentlyContinue) { return $true }
  if ($DryRun) { return $true }

  try {
    Invoke-Expression "& {$(Invoke-RestMethod get.scoop.sh)} -RunAsAdmin"

    $scoopShims = Join-Path $env:USERPROFILE "scoop\shims"
    if (Test-Path $scoopShims) {
      $env:Path = "$env:Path;$scoopShims"
    }

    return $null -ne (Get-Command scoop -ErrorAction SilentlyContinue)
  }
  catch {
    return $false
  }
}

function Add-ScoopBuckets {
  $buckets = @('extras', 'games', 'java', 'nerd-fonts', 'nonportable')

  foreach ($bucket in $buckets) {
    if ($DryRun) { continue }

    scoop bucket add $bucket | Out-Null
  }
}

function Install-ScoopApps {
  param([array]$Apps)

  $failed = @()

  foreach ($app in $Apps) {
    $pkg = if ($app -is [string]) { $app } else { $app.name }

    if ($DryRun) { continue }

    try {
      scoop install $pkg
      if ($LASTEXITCODE -ne 0) { $failed += $pkg }
    }
    catch {
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

function Import-ScoopRegistrySettings {
  $regFiles = @{
    "7-Zip context menu"      = "$env:USERPROFILE\scoop\apps\7zip\current\install-context.reg"
    "Git file associations"   = "$env:USERPROFILE\scoop\apps\git\current\install-file-associations.reg"
    "Python PEP 514 registry" = "$env:USERPROFILE\scoop\apps\python\current\install-pep-514.reg"
  }

  foreach ($desc in $regFiles.Keys) {
    $path = $regFiles[$desc]
    if (Test-Path $path) {
      else {
        reg import "`"$path`"" 2>$null
      }
    }
  }
}

function Install-AppFromUrl {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [string]$FileName
  )

  $TempDir = "$env:TEMP\AppInstall"
  if (-Not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir | Out-Null
  }

  if (-Not $FileName) {
    $FileName = [System.IO.Path]::GetFileName($Url)
    if (-Not $FileName) { $FileName = "installer.exe" }
  }

  $InstallerPath = Join-Path $TempDir $FileName

  Write-Host "Downloading..."
  curl -L $Url -o $InstallerPath

  if (-Not (Test-Path $InstallerPath)) {
    Write-Error "Download failed."
    return
  }

  Write-Host "Running installer..."
  Start-Process -FilePath $InstallerPath -Wait

  Remove-Item $InstallerPath -Force
  Write-Host "Done."
}

function Set-Wallpaper {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ImagePath
  )

  if (-not (Test-Path $ImagePath)) {
    Write-Error "File does not exist: $ImagePath"
    return
  }

  Add-Type @"
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

  # 20 = SPI_SETDESKWALLPAPER, 3 = SPIF_UPDATEINIFILE + SPIF_SENDCHANGE
  [Wallpaper]::SystemParametersInfo(20, 0, $ImagePath, 3)
  Write-Host "Wallpaper set to $ImagePath" -ForegroundColor Green
}


# ---------- Main execution ----------
Write-Host "Starting Scoop setup..." -ForegroundColor Cyan

if (-not (Install-Scoop)) {
  Write-Error "Scoop installation failed"
  exit 1
}

scoop config aria2-enabled true
scoop config cache-autoupdate true
scoop config cache-max 5
scoop config aria2-options "--max-connection-per-server=16 --split=16 --retry-wait=5"

Add-ScoopBuckets

$scoopApps = @(
  'main/aria2',
  'main/sudo',
  'extras/vcredist-aio',
  'nonportable/equalizer-apo-np',
  'main/7zip',
  'main/git',
  'main/pwsh',
  'main/starship',
  'main/clink',
  'main/nodejs',
  'main/fastfetch',
  'main/python',
  'main/adb',
  'main/cmake',
  'main/mingw',
  'main/curl',
  'main/wget',
  'main/ripgrep',
  'main/fd',
  'main/fzf',
  'main/bun',
  'main/neovim',
  'main/speedtest-cli',
  'main/yt-dlp',
  'main/eza',
  'main/ffmpeg',
  'main/gzip',
  'main/unzip',
  'java/openjdk',
  'extras/brave',
  'extras/vencord-installer',
  'extras/windows-terminal',
  'extras/notepadplusplus',
  'extras/vscode',
  'extras/vlc',
  'extras/nomacs',
  'extras/obs-studio',
  'extras/qbittorrent-enhanced',
  'extras/spotify',
  'extras/everything',
  'extras/wiztree',
  'extras/sysinternals',
  'extras/hwinfo',
  'extras/bleachbit',
  'extras/equalizer-apo',
  'extras/krita',
  'extras/epicgameslauncher',
  'extras/geforce-now',
  'extras/revouninstaller',
  'extras/anytype',
  'extras/youtube-music',
  'extras/psreadline',
  'extras/posh-git',
  'extras/ddu',
  'games/steam',
  'games/prismlauncher',
  'nerd-fonts/FiraCode',
  'nerd-fonts/Cascadia-Code',
  'nerd-fonts/Hack-NF',
  'nerd-fonts/JetBrainsMono-NF'
)

Install-ScoopApps -Apps $scoopApps

$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

Install-AppFromUrl -Url "https://discord.com/api/download?platform=win&arch=x64"

if (-not (Set-DotfilesConfiguration)) {
  Write-Warning "Dotfiles configuration failed"
}

Set-Wallpaper -ImagePath "$env:USERPROFILE\.dotfiles\wallpapers\background.jpg"

Import-ScoopRegistrySettings

git clone https://github.com/nvim-lua/kickstart.nvim.git "${env:LOCALAPPDATA}\nvim"

scoop update
scoop update *
scoop cache rm *
scoop cleanup *
