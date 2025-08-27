# Function to check admin privileges
function Test-AdminPrivileges {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
  if (-not $isAdmin) {
    Write-Error "This script requires admin privileges. Please run it as an administrator."
    exit 1
  }
}

# Function to create a symbolic link with better error handling
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
      return $false
    }

    # Create parent directory if it doesn't exist
    $parentDir = Split-Path -Path $Path -Parent
    if (-not (Test-Path $parentDir)) {
      New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
      Write-Host "Created directory: $parentDir" -ForegroundColor Green
    }

    if ((Test-Path $Path) -and $Force) {
      Remove-Item -Path $Path -Force -Recurse
      Write-Host "Existing item at '$Path' removed." -ForegroundColor Yellow
    }

    if ($LinkType -eq 'Symbolic') {
      New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force | Out-Null
    }
    elseif ($LinkType -eq 'Hard') {
      New-Item -ItemType HardLink -Path $Path -Target $Target -Force | Out-Null
    }

    Write-Host "Successfully created $LinkType link: $Path -> $Target" -ForegroundColor Green
    return $true
  }
  catch {
    Write-Error "Error creating link: $($_.Exception.Message)"
    return $false
  }
}

# Function to install Scoop with better validation
function Install-Scoop {
  Write-Host "Checking Scoop installation..." -ForegroundColor Cyan

  if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Host "Scoop is already installed." -ForegroundColor Green
    return $true
  }

  try {
    Write-Host "Installing Scoop..." -ForegroundColor Yellow
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

    # Verify installation
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
      Write-Host "Scoop installed successfully!" -ForegroundColor Green
      return $true
    }
    else {
      Write-Error "Scoop installation failed - command not found after install"
      return $false
    }
  }
  catch {
    Write-Error "Error installing Scoop: $($_.Exception.Message)"
    return $false
  }
}

# Function to add Scoop buckets with progress tracking
function Add-ScoopBuckets {
  $buckets = @('extras', 'games', 'java', 'nerd-fonts')
  $successCount = 0

  Write-Host "Adding Scoop buckets..." -ForegroundColor Cyan

  foreach ($bucket in $buckets) {
    try {
      Write-Host "  Adding bucket: $bucket" -ForegroundColor Yellow
      $result = scoop bucket add $bucket 2>&1

      if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Successfully added bucket: $bucket" -ForegroundColor Green
        $successCount++
      }
      else {
        Write-Warning "  ✗ Failed to add bucket '$bucket': $result"
      }
    }
    catch {
      Write-Warning "  ✗ Error adding bucket '$bucket': $($_.Exception.Message)"
    }
  }

  Write-Host "Successfully added $successCount/$($buckets.Count) buckets." -ForegroundColor Cyan
}

# Function to install Scoop apps with proper error handling
function Install-ScoopApps {
  param (
    [array]$apps
  )

  $successCount = 0
  $failedApps = @()

  Write-Host "Installing applications..." -ForegroundColor Cyan

  foreach ($app in $apps) {
    try {
      Write-Host "  Installing: $($app.name)" -ForegroundColor Yellow

      if ($app.params) {
        $result = scoop install $app.name $app.params 2>&1
      }
      else {
        $result = scoop install $app.name 2>&1
      }

      if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Successfully installed: $($app.name)" -ForegroundColor Green
        $successCount++
      }
      else {
        Write-Warning "  ✗ Failed to install $($app.name): $result"
        $failedApps += $app.name
      }
    }
    catch {
      Write-Warning "  ✗ Error installing $($app.name): $($_.Exception.Message)"
      $failedApps += $app.name
    }
  }

  Write-Host "Installation complete: $successCount/$($apps.Count) apps installed successfully." -ForegroundColor Cyan

  if ($failedApps.Count -gt 0) {
    Write-Warning "Failed to install: $($failedApps -join ', ')"
  }
}

# Function to validate git availability
function Test-GitAvailability {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "Git is not available. Please ensure git is installed and in PATH."
    return $false
  }
  return $true
}

# Function to set up dotfiles with better validation
function Set-DotfilesConfiguration {
  Write-Host "Setting up dotfiles configuration..." -ForegroundColor Cyan

  if (-not (Test-GitAvailability)) {
    return $false
  }

  $dotfilesPath = "$env:USERPROFILE\.dotfiles"

  # Clean existing dotfiles
  if (Test-Path -Path $dotfilesPath) {
    Write-Host "Removing existing dotfiles..." -ForegroundColor Yellow
    Remove-Item -Path $dotfilesPath -Recurse -Force
  }

  try {
    Write-Host "Cloning dotfiles repository..." -ForegroundColor Yellow
    git clone https://github.com/itzL1m4k/.dotfiles.git $dotfilesPath

    if (-not (Test-Path -Path $dotfilesPath)) {
      Write-Error "Failed to clone dotfiles repository"
      return $false
    }
  }
  catch {
    Write-Error "Error cloning dotfiles: $($_.Exception.Message)"
    return $false
  }

  # Define symbolic links configuration
  $links = @(
    @{Path = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"; Target = "$dotfilesPath\terminal\settings.json" },
    @{Path = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"; Target = "$dotfilesPath\powershell\powershell.ps1" },
    @{Path = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"; Target = "$dotfilesPath\powershell\powershell.ps1" },
    @{Path = "$env:APPDATA\Notepad++\themes\catppuccin-mocha.xml"; Target = "$dotfilesPath\notepad\catppuccin-mocha.xml" },
    @{Path = "$env:USERPROFILE\.config\starship.toml"; Target = "$dotfilesPath\.config\starship.toml" },
    @{Path = "$env:LOCALAPPDATA\clink\starship.lua"; Target = "$dotfilesPath\clink\starship.lua" },
    @{Path = "$env:USERPROFILE\.bash_profile"; Target = "$dotfilesPath\.bash_profile" },
    @{Path = "$env:USERPROFILE\.gitconfig"; Target = "$dotfilesPath\.gitconfig" }
  )

  $linkSuccessCount = 0
  Write-Host "Creating symbolic links..." -ForegroundColor Yellow

  foreach ($link in $links) {
    if (New-Link -Path $link.Path -Target $link.Target -LinkType "Symbolic" -Force) {
      $linkSuccessCount++
    }
  }

  Write-Host "Created $linkSuccessCount/$($links.Count) symbolic links successfully." -ForegroundColor Cyan

  # Import registry settings
  $regPath = "$dotfilesPath\registry\registry.reg"
  if (Test-Path -Path $regPath) {
    try {
      Write-Host "Importing registry settings..." -ForegroundColor Yellow
      Start-Process -FilePath "reg.exe" -ArgumentList "import", $regPath -Verb RunAs -Wait
      Write-Host "Registry settings imported successfully." -ForegroundColor Green
    }
    catch {
      Write-Warning "Failed to import registry settings: $($_.Exception.Message)"
    }
  }
  else {
    Write-Warning "Registry file not found: $regPath"
  }

  return $true
}

# Main function with better error handling and progress tracking
function Main {
  $startTime = Get-Date
  Write-Host "=== Windows Development Environment Setup ===" -ForegroundColor Magenta
  Write-Host "Started at: $startTime" -ForegroundColor Gray

  # Check admin privileges
  Test-AdminPrivileges

  # Install Scoop
  if (-not (Install-Scoop)) {
    Write-Error "Setup failed: Could not install Scoop"
    return 1
  }

  # Add buckets
  Add-ScoopBuckets

  # Define applications to install
  $scoopApps = @(
    # Essential system components
    @{name = "extras/vcredist-aio" },

    # Core utilities and tools
    @{name = "main/7zip" },
    @{name = "main/git" },
    @{name = "main/pwsh" },
    @{name = "main/starship" },
    @{name = "main/clink" },
    @{name = "main/nodejs" },
    @{name = "main/fastfetch" },

    # Development tools
    @{name = "main/cmake" },
    @{name = "main/mingw" },
    @{name = "main/curl" },
    @{name = "main/wget" },
    @{name = "main/ripgrep" },
    @{name = "main/fd" },
    @{name = "main/fzf" },

    # Java development
    @{name = "java/openjdk" },

    # Browsers and communication
    @{name = "extras/brave" },
    @{name = "extras/discord" },

    # Terminal and development environment
    @{name = "extras/windows-terminal" },
    @{name = "extras/notepadplusplus" },
    @{name = "extras/vscode" },

    # Media and entertainment
    @{name = "extras/vlc" },
    @{name = "extras/nomacs" },
    @{name = "extras/obs-studio" },
    @{name = "extras/qbittorrent-enhanced" },
    @{name = "extras/spotify" },

    # System utilities
    @{name = "extras/everything" },
    @{name = "extras/wiztree" },
    @{name = "extras/sysinternals" },
    @{name = "extras/hwinfo" },
    @{name = "extras/bleachbit" },
    @{name = "extras/equalizer-apo" },

    # Creative tools
    @{name = "extras/krita" },

    # Gaming
    @{name = "extras/epicgameslauncher" },
    @{name = "extras/geforce-now" },
    @{name = "games/steam" },

    # Fonts
    @{name = "nerd-fonts/FiraCode" },
    @{name = "nerd-fonts/Cascadia-Code" }
  )

  # Install applications
  Install-ScoopApps -apps $scoopApps

  # Refresh PATH to include Scoop
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

  # Set up dotfiles
  if (-not (Set-DotfilesConfiguration)) {
    Write-Warning "Dotfiles configuration failed, but continuing..."
  }

  $endTime = Get-Date
  $duration = $endTime - $startTime

  Write-Host "=== Setup Complete ===" -ForegroundColor Magenta
  Write-Host "Completed at: $endTime" -ForegroundColor Gray
  Write-Host "Total duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor Gray
  Write-Host "Please restart your shell to ensure all changes take effect." -ForegroundColor Yellow

  return 0
}

# Run main function
Main
