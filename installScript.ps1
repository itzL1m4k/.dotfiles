<#
.SYNOPSIS
    Automated Windows setup script with dotfiles configuration.
.DESCRIPTION
    Installs essential applications via winget, configures dotfiles with symbolic links,
    and sets up development environment.
.PARAMETER Force
    Force overwrite existing symbolic links and configurations.
.PARAMETER DotfilesRepo
    Git repository URL for dotfiles.
.EXAMPLE
    .\setup.ps1 -Force
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Force overwrite existing configurations")]
    [switch]$Force,
    
    [Parameter(HelpMessage = "Dotfiles repository URL")]
    [string]$DotfilesRepo = 'https://github.com/itzL1m4k/.dotfiles.git'
)

#Requires -Version 5.1

# ============================================================================
# Configuration
# ============================================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Script:Config = @{
    DotfilesPath = Join-Path $env:USERPROFILE '.dotfiles'
    TempDir      = Join-Path $env:TEMP 'WindowsSetup'
    LogFile      = Join-Path $env:TEMP 'setup-log.txt'
}

# ============================================================================
# Logging Functions
# ============================================================================

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    $colors = @{
        Info    = 'Cyan'
        Success = 'Green'
        Warning = 'Yellow'
        Error   = 'Red'
    }
    
    Write-Host $logMessage -ForegroundColor $colors[$Level]
    Add-Content -Path $Script:Config.LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

# ============================================================================
# Utility Functions
# ============================================================================

function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Initialize-Setup {
    Write-Log "Initializing setup..." -Level Info
    
    if (-not (Test-Path $Script:Config.TempDir)) {
        New-Item -ItemType Directory -Path $Script:Config.TempDir -Force | Out-Null
    }
    
    if (Test-Path $Script:Config.LogFile) {
        Remove-Item $Script:Config.LogFile -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# Winget Functions
# ============================================================================

function Install-Winget {
    Write-Log "Checking winget availability..." -Level Info
    
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Log "Winget is already installed" -Level Success
        return $true
    }
    
    try {
        Write-Log "Installing winget..." -Level Info
        
        $wingetPackage = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
        
        if (-not $wingetPackage) {
            $wingetUrl = 'https://aka.ms/getwinget'
            $wingetPath = Join-Path $Script:Config.TempDir 'winget.msixbundle'
            
            Invoke-WebRequest -Uri $wingetUrl -OutFile $wingetPath -UseBasicParsing
            Add-AppxPackage -Path $wingetPath
            
            Remove-Item $wingetPath -Force -ErrorAction SilentlyContinue
        }
        
        $installed = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
        
        if ($installed) {
            Write-Log "Winget installed successfully" -Level Success
        } else {
            Write-Log "Failed to install winget" -Level Error
        }
        
        return $installed
    }
    catch {
        Write-Log "Error installing winget: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Install-WingetApplication {
    param(
        [Parameter(Mandatory)]
        [string]$AppId,
        
        [string]$AppName
    )
    
    $displayName = if ($AppName) { $AppName } else { $AppId }
    
    try {
        Write-Log "Installing $displayName..." -Level Info
        
        $result = winget install --id $AppId `
            --silent `
            --accept-source-agreements `
            --accept-package-agreements `
            --disable-interactivity `
            2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "$displayName installed successfully" -Level Success
            return $true
        } else {
            Write-Log "$displayName installation failed (exit code: $LASTEXITCODE)" -Level Warning
            return $false
        }
    }
    catch {
        Write-Log "Error installing $displayName : $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Install-WingetApps {
    param(
        [Parameter(Mandatory)]
        [string[]]$AppIds
    )
    
    Write-Log "Installing $($AppIds.Count) applications..." -Level Info
    
    $installed = 0
    $failed = 0
    
    foreach ($appId in $AppIds) {
        if (Install-WingetApplication -AppId $appId) {
            $installed++
        } else {
            $failed++
        }
    }
    
    Write-Log "Installation complete: $installed succeeded, $failed failed" -Level Info
}

# ============================================================================
# Git Configuration Functions
# ============================================================================

function Install-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Log "Git is already installed" -Level Success
        return $true
    }
    
    Write-Log "Git not found, installing..." -Level Warning
    return Install-WingetApplication -AppId 'Git.Git' -AppName 'Git'
}

function Initialize-GitConfig {
    try {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Log "Git not available, skipping git configuration" -Level Warning
            return
        }
        
        Write-Log "Configuring git credential helper..." -Level Info
        git config --global credential.helper manager 2>&1 | Out-Null
        Write-Log "Git configured successfully" -Level Success
    }
    catch {
        Write-Log "Error configuring git: $($_.Exception.Message)" -Level Warning
    }
}

# ============================================================================
# Symbolic Link Functions
# ============================================================================

function New-SymbolicLink {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$Target
    )
    
    if (-not (Test-Path $Target)) {
        Write-Log "Target does not exist: $Target" -Level Warning
        return $false
    }
    
    # Create parent directory if needed
    $parentPath = Split-Path -Parent $Path
    if ($parentPath -and -not (Test-Path $parentPath)) {
        try {
            New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
            Write-Log "Created directory: $parentPath" -Level Info
        }
        catch {
            Write-Log "Failed to create directory: $parentPath" -Level Error
            return $false
        }
    }
    
    # Handle existing path
    if (Test-Path $Path) {
        $item = Get-Item $Path -Force
        
        if ($item.LinkType -eq 'SymbolicLink') {
            $currentTarget = $item.Target
            if ($currentTarget -eq $Target) {
                Write-Log "Symlink already exists and is correct: $Path" -Level Info
                return $true
            }
        }
        
        if ($Force) {
            try {
                Remove-Item $Path -Force -Recurse -ErrorAction Stop
                Write-Log "Removed existing item: $Path" -Level Info
            }
            catch {
                Write-Log "Failed to remove existing item: $Path" -Level Error
                return $false
            }
        } else {
            Write-Log "Path already exists (use -Force to overwrite): $Path" -Level Warning
            return $false
        }
    }
    
    # Create symbolic link
    try {
        $targetItem = Get-Item $Target
        
        if ($targetItem.PSIsContainer) {
            # Use cmd for directory junction (more compatible)
            $result = cmd /c mklink /D "`"$Path`"" "`"$Target`"" 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "mklink failed: $result"
            }
        } else {
            # Use PowerShell for file symlink
            New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force | Out-Null
        }
        
        Write-Log "Created symlink: $Path -> $Target" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to create symlink: $Path -> $Target ($($_.Exception.Message))" -Level Error
        return $false
    }
}

# ============================================================================
# Dotfiles Configuration
# ============================================================================

function Install-DotfilesRepository {
    param(
        [Parameter(Mandatory)]
        [string]$RepoUrl,
        
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )
    
    Write-Log "Installing dotfiles from: $RepoUrl" -Level Info
    
    # Backup existing .gitconfig if it's a symlink
    $gitConfigPath = Join-Path $env:USERPROFILE '.gitconfig'
    $gitConfigBackup = $null
    
    if (Test-Path $gitConfigPath) {
        $gitConfigItem = Get-Item $gitConfigPath -Force
        if ($gitConfigItem.LinkType -eq 'SymbolicLink') {
            $gitConfigBackup = Join-Path $Script:Config.TempDir '.gitconfig.backup'
            try {
                Copy-Item $gitConfigPath $gitConfigBackup -Force
                Remove-Item $gitConfigPath -Force
                Write-Log "Backed up .gitconfig temporarily" -Level Info
            }
            catch {
                Write-Log "Failed to backup .gitconfig: $($_.Exception.Message)" -Level Warning
            }
        }
    }
    
    # Remove existing dotfiles directory
    if (Test-Path $DestinationPath) {
        try {
            Remove-Item $DestinationPath -Recurse -Force -ErrorAction Stop
            Write-Log "Removed existing dotfiles directory" -Level Info
        }
        catch {
            Write-Log "Failed to remove existing dotfiles: $($_.Exception.Message)" -Level Warning
        }
    }
    
    # Clone repository
    try {
        $cloneResult = git clone --depth 1 $RepoUrl $DestinationPath 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "Git clone failed: $cloneResult"
        }
        
        Write-Log "Dotfiles cloned successfully" -Level Success
        
        # Restore .gitconfig backup if it exists
        if ($gitConfigBackup -and (Test-Path $gitConfigBackup)) {
            Remove-Item $gitConfigBackup -Force -ErrorAction SilentlyContinue
        }
        
        return $true
    }
    catch {
        Write-Log "Failed to clone dotfiles: $($_.Exception.Message)" -Level Error
        
        # Restore backup on failure
        if ($gitConfigBackup -and (Test-Path $gitConfigBackup)) {
            Copy-Item $gitConfigBackup $gitConfigPath -Force -ErrorAction SilentlyContinue
            Remove-Item $gitConfigBackup -Force -ErrorAction SilentlyContinue
        }
        
        return $false
    }
}

function Set-DotfilesSymlinks {
    param(
        [Parameter(Mandatory)]
        [string]$DotfilesPath
    )
    
    Write-Log "Creating symbolic links for dotfiles..." -Level Info
    
    $symlinkMappings = @(
        @{
            Path   = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
            Target = "$DotfilesPath\terminal\settings.json"
        },
        @{
            Path   = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
            Target = "$DotfilesPath\powershell\powershell.ps1"
        },
        @{
            Path   = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
            Target = "$DotfilesPath\powershell\powershell.ps1"
        },
        @{
            Path   = "$env:APPDATA\Notepad++\themes\catppuccin-mocha.xml"
            Target = "$DotfilesPath\notepad\catppuccin-mocha.xml"
        },
        @{
            Path   = "$env:USERPROFILE\.config\starship.toml"
            Target = "$DotfilesPath\.config\starship.toml"
        },
        @{
            Path   = "$env:LOCALAPPDATA\clink\starship.lua"
            Target = "$DotfilesPath\clink\starship.lua"
        },
        @{
            Path   = "$env:USERPROFILE\.bash_profile"
            Target = "$DotfilesPath\.bash_profile"
        },
        @{
            Path   = "$env:USERPROFILE\.gitconfig"
            Target = "$DotfilesPath\.gitconfig"
        }
    )
    
    $created = 0
    $failed = 0
    
    foreach ($mapping in $symlinkMappings) {
        if (New-SymbolicLink -Path $mapping.Path -Target $mapping.Target) {
            $created++
        } else {
            $failed++
        }
    }
    
    Write-Log "Symlink creation complete: $created succeeded, $failed failed" -Level Info
}

function Import-RegistrySettings {
    param(
        [Parameter(Mandatory)]
        [string]$DotfilesPath
    )
    
    $registryFile = Join-Path $DotfilesPath 'registry\registry.reg'
    
    if (-not (Test-Path $registryFile)) {
        Write-Log "Registry file not found, skipping registry import" -Level Info
        return
    }
    
    try {
        Write-Log "Importing registry settings..." -Level Info
        $result = reg import "`"$registryFile`"" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Registry settings imported successfully" -Level Success
        } else {
            Write-Log "Registry import failed: $result" -Level Warning
        }
    }
    catch {
        Write-Log "Error importing registry settings: $($_.Exception.Message)" -Level Warning
    }
}

function Set-DesktopWallpaper {
    param(
        [Parameter(Mandatory)]
        [string]$ImagePath
    )
    
    if (-not (Test-Path $ImagePath)) {
        Write-Log "Wallpaper file not found: $ImagePath" -Level Warning
        return
    }
    
    try {
        Write-Log "Setting desktop wallpaper..." -Level Info
        
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class WallpaperHelper {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    
    public const int SPI_SETDESKWALLPAPER = 0x0014;
    public const int SPIF_UPDATEINIFILE = 0x01;
    public const int SPIF_SENDCHANGE = 0x02;
}
"@ -ErrorAction SilentlyContinue
        
        $fullPath = (Resolve-Path $ImagePath).Path
        $result = [WallpaperHelper]::SystemParametersInfo(
            [WallpaperHelper]::SPI_SETDESKWALLPAPER,
            0,
            $fullPath,
            [WallpaperHelper]::SPIF_UPDATEINIFILE -bor [WallpaperHelper]::SPIF_SENDCHANGE
        )
        
        if ($result -ne 0) {
            Write-Log "Wallpaper set successfully" -Level Success
        } else {
            Write-Log "Failed to set wallpaper" -Level Warning
        }
    }
    catch {
        Write-Log "Error setting wallpaper: $($_.Exception.Message)" -Level Warning
    }
}

# ============================================================================
# Application Installation Functions
# ============================================================================

function Install-ApplicationFromUrl {
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        
        [string]$FileName,
        
        [string]$AppName
    )
    
    $displayName = if ($AppName) { $AppName } else { 'Application' }
    
    try {
        Write-Log "Downloading $displayName..." -Level Info
        
        if (-not $FileName) {
            $FileName = [System.IO.Path]::GetFileName($Url)
        }
        
        $installerPath = Join-Path $Script:Config.TempDir $FileName
        
        Invoke-WebRequest -Uri $Url -OutFile $installerPath -UseBasicParsing
        
        Write-Log "Installing $displayName..." -Level Info
        Start-Process -FilePath $installerPath -Wait -NoNewWindow
        
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        
        Write-Log "$displayName installed successfully" -Level Success
        return $true
    }
    catch {
        Write-Log "Error installing $displayName : $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Install-NeovimKickstart {
    $nvimPath = Join-Path $env:LOCALAPPDATA 'nvim'
    
    try {
        Write-Log "Installing Neovim Kickstart configuration..." -Level Info
        
        if (Test-Path $nvimPath) {
            Remove-Item $nvimPath -Recurse -Force -ErrorAction Stop
        }
        
        $cloneResult = git clone https://github.com/nvim-lua/kickstart.nvim.git $nvimPath 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Neovim Kickstart installed successfully" -Level Success
        } else {
            Write-Log "Failed to install Neovim Kickstart: $cloneResult" -Level Warning
        }
    }
    catch {
        Write-Log "Error installing Neovim Kickstart: $($_.Exception.Message)" -Level Warning
    }
}

# ============================================================================
# Task Scheduler Functions
# ============================================================================

function Register-LogonTask {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,
        
        [Parameter(Mandatory)]
        [string]$TaskName
    )
    
    if (-not (Test-Path $ScriptPath)) {
        Write-Log "Task script not found: $ScriptPath" -Level Warning
        return
    }
    
    try {
        Write-Log "Registering scheduled task: $TaskName" -Level Info
        
        # Remove existing task
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        }
        
        # Create new task
        $action = New-ScheduledTaskAction -Execute $ScriptPath
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId "BUILTIN\Users" -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        
        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Force | Out-Null
        
        Write-Log "Scheduled task registered successfully" -Level Success
    }
    catch {
        Write-Log "Error registering scheduled task: $($_.Exception.Message)" -Level Warning
    }
}

# ============================================================================
# Main Execution
# ============================================================================

function Invoke-WindowsSetup {
    try {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  Windows Setup Script" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan
        
        Initialize-Setup
        
        # Check administrator privileges
        if (-not (Test-Administrator)) {
            Write-Log "This script requires administrator privileges for some operations" -Level Warning
            Write-Log "Some features may not work correctly without elevation" -Level Warning
        }
        
        # Install Winget
        if (-not (Install-Winget)) {
            Write-Log "Failed to install winget. Exiting..." -Level Error
            return
        }
        
        # Install applications
        Write-Log "`n--- Installing Applications ---" -Level Info
        
        $applications = @(
            '7zip.7zip',
            'Git.Git',
            'Microsoft.PowerShell',
            'Starship.Starship',
            'chrisant996.Clink',
            'Brave.Brave',
            'Discord.Discord',
            'Microsoft.WindowsTerminal',
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
            'RevoUninstaller.RevoUninstaller'
        )
        
        Install-WingetApps -AppIds $applications
        
        # Install fonts
        Write-Log "`n--- Installing Fonts ---" -Level Info
        $fonts = @(
            'DEVCOM.JetBrainsMonoNerdFont',
            'Microsoft.CascadiaCode'
        )
        Install-WingetApps -AppIds $fonts
        
        # Install SteelSeries GG
        Write-Log "`n--- Installing Additional Applications ---" -Level Info
        Install-ApplicationFromUrl `
            -Url "https://steelseries.com/gg/downloads/gg/latest/windows" `
            -FileName "SteelSeriesGG.exe" `
            -AppName "SteelSeries GG"
        
        # Configure Git
        Write-Log "`n--- Configuring Git ---" -Level Info
        Initialize-GitConfig
        
        # Setup Dotfiles
        Write-Log "`n--- Setting up Dotfiles ---" -Level Info
        
        if (Install-DotfilesRepository -RepoUrl $DotfilesRepo -DestinationPath $Script:Config.DotfilesPath) {
            Set-DotfilesSymlinks -DotfilesPath $Script:Config.DotfilesPath
            Import-RegistrySettings -DotfilesPath $Script:Config.DotfilesPath
            
            # Set wallpaper
            $wallpaperPath = Join-Path $Script:Config.DotfilesPath 'wallpapers\background.jpg'
            if (Test-Path $wallpaperPath) {
                Set-DesktopWallpaper -ImagePath $wallpaperPath
            }
            
            # Register cleanup task
            $clearBatPath = Join-Path $Script:Config.DotfilesPath 'clear.bat'
            if (Test-Path $clearBatPath) {
                Register-LogonTask -ScriptPath $clearBatPath -TaskName "clear-temp"
            }
        }
        
        # Install Neovim configuration
        # Write-Log "`n--- Installing Neovim Configuration ---" -Level Info
        # Install-NeovimKickstart
        
        # Upgrade all packages
        Write-Log "`n--- Upgrading All Packages ---" -Level Info
        try {
            winget upgrade --all --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            Write-Log "Package upgrade completed" -Level Success
        }
        catch {
            Write-Log "Error during package upgrade: $($_.Exception.Message)" -Level Warning
        }
        
        # Cleanup
        Write-Log "`n--- Cleaning Up ---" -Level Info
        if (Test-Path $Script:Config.TempDir) {
            Remove-Item $Script:Config.TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "  Setup Complete!" -ForegroundColor Green
        Write-Host "========================================`n" -ForegroundColor Green
        Write-Log "Setup completed successfully!" -Level Success
        Write-Log "Log file: $($Script:Config.LogFile)" -Level Info
        
        Write-Host "`nPlease restart your terminal to apply all changes.`n" -ForegroundColor Yellow
    }
    catch {
        Write-Log "Fatal error during setup: $($_.Exception.Message)" -Level Error
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
        throw
    }
}

# Execute main function
Invoke-WindowsSetup
