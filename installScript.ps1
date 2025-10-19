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

        $output = $result | Out-String

        # Analiza kodu wyjścia i treści wyjścia
        switch ($LASTEXITCODE) {
            0 {
                Write-Log "$displayName installed successfully" -Level Success
                return @{ Success = $true; ExitCode = 0; Message = "Installation completed successfully" }
            }
            -1978335189 {
                # 0x8A15000B - No applicable update found
                if ($output -match "No applicable update found|No newer package versions are available") {
                    Write-Log "$displayName is already installed with the latest version" -Level Info
                    return @{ Success = $true; ExitCode = $LASTEXITCODE; Message = "Already up to date" }
                } else {
                    Write-Log "$displayName is already installed" -Level Info
                    return @{ Success = $true; ExitCode = $LASTEXITCODE; Message = "Already installed" }
                }
            }
            -1978335135 {
                # 0x8A150041 - No package found matching input criteria
                Write-Log "$displayName not found in winget repository (ID: $AppId)" -Level Error
                return @{ Success = $false; ExitCode = $LASTEXITCODE; Message = "Package not found" }
            }
            -1978335215 {
                # 0x8A150031 - Install package command failed
                Write-Log "$displayName installation failed - installer returned an error" -Level Error
                return @{ Success = $false; ExitCode = $LASTEXITCODE; Message = "Installer failed" }
            }
            -1978335212 {
                # 0x8A150034 - Download failed
                Write-Log "$displayName download failed - check network connection" -Level Error
                return @{ Success = $false; ExitCode = $LASTEXITCODE; Message = "Download failed" }
            }
            -1978335214 {
                # 0x8A150032 - Hash mismatch
                Write-Log "$displayName installation failed - file integrity check failed" -Level Error
                return @{ Success = $false; ExitCode = $LASTEXITCODE; Message = "Hash verification failed" }
            }
            -1978335222 {
                # 0x8A15002A - Package agreement not accepted
                Write-Log "$displayName requires agreement acceptance" -Level Warning
                return @{ Success = $false; ExitCode = $LASTEXITCODE; Message = "Agreement not accepted" }
            }
            -1978335160 {
                # 0x8A150058 - Install requires elevation
                Write-Log "$displayName requires administrator privileges" -Level Error
                return @{ Success = $false; ExitCode = $LASTEXITCODE; Message = "Elevation required" }
            }
            -1978335221 {
                # 0x8A15002B - System shutdown in progress
                Write-Log "$displayName installation blocked - system shutdown in progress" -Level Warning
                return @{ Success = $false; ExitCode = $LASTEXITCODE; Message = "System shutting down" }
            }
            -1978335213 {
                # 0x8A150033 - Internal error
                Write-Log "$displayName installation failed - winget internal error" -Level Error
                return @{ Success = $false; ExitCode = $LASTEXITCODE; Message = "Internal winget error" }
            }
            -1978335216 {
                # 0x8A150030 - Installer failed to complete
                if ($output -match "0x80070652") {
                    Write-Log "$displayName installation blocked - another installation is in progress" -Level Warning
                    return @{ Success = $false; ExitCode = $LASTEXITCODE; Message = "Another installation in progress" }
                } elseif ($output -match "0x80070005") {
                    Write-Log "$displayName installation failed - access denied" -Level Error
                    return @{ Success = $false; ExitCode = $LASTEXITCODE; Message = "Access denied" }
                } elseif ($output -match "0x800706be") {
                    Write-Log "$displayName installation failed - RPC server unavailable" -Level Error
                    return @{ Success = $false; ExitCode = $LASTEXITCODE; Message = "RPC server unavailable" }
                } else {
                    Write-Log "$displayName installation failed (installer exit code in output)" -Level Error
                    return @{ Success = $false; ExitCode = $LASTEXITCODE; Message = "Installer error" }
                }
            }
            default {
                # Dodatkowa analiza wyjścia dla nieznanych kodów błędów
                if ($output -match "No package found|No packages were found") {
                    Write-Log "$displayName not found - invalid package ID: $AppId" -Level Error
                    return @{ Success = $false; ExitCode = $LASTEXITCODE; Message = "Package not found" }
                } elseif ($output -match "already installed") {
                    Write-Log "$displayName is already installed" -Level Info
                    return @{ Success = $true; ExitCode = $LASTEXITCODE; Message = "Already installed" }
                } elseif ($output -match "requires interactive") {
                    Write-Log "$displayName requires interactive installation" -Level Warning
                    return @{ Success = $false; ExitCode = $LASTEXITCODE; Message = "Interactive installation required" }
                } elseif ($output -match "blocked by policy") {
                    Write-Log "$displayName installation blocked by group policy" -Level Error
                    return @{ Success = $false; ExitCode = $LASTEXITCODE; Message = "Blocked by policy" }
                } else {
                    Write-Log "$displayName installation failed with exit code: $LASTEXITCODE" -Level Warning
                    Write-Log "Output: $($output.Substring(0, [Math]::Min(200, $output.Length)))" -Level Debug
                    return @{ Success = $false; ExitCode = $LASTEXITCODE; Message = "Unknown error (code: $LASTEXITCODE)" }
                }
            }
        }
    }
    catch {
        Write-Log "Error installing $displayName : $($_.Exception.Message)" -Level Error
        return @{ Success = $false; ExitCode = -1; Message = "Exception: $($_.Exception.Message)" }
    }
}

function Install-WingetApps {
    param(
        [Parameter(Mandatory)]
        [string[]]$AppIds
    )

    Write-Log "Installing $($AppIds.Count) applications..." -Level Info

    $results = @{
        Total = $AppIds.Count
        Succeeded = 0
        Failed = 0
        AlreadyInstalled = 0
        Details = @()
    }

    foreach ($appId in $AppIds) {
        $installResult = Install-WingetApplication -AppId $appId

        $results.Details += [PSCustomObject]@{
            AppId = $appId
            Success = $installResult.Success
            ExitCode = $installResult.ExitCode
            Message = $installResult.Message
        }

        if ($installResult.Success) {
            if ($installResult.Message -match "Already") {
                $results.AlreadyInstalled++
            } else {
                $results.Succeeded++
            }
        } else {
            $results.Failed++
        }
    }

    Write-Log "Installation complete: $($results.Succeeded) newly installed, $($results.AlreadyInstalled) already installed, $($results.Failed) failed" -Level Info

    # Podsumowanie błędów
    if ($results.Failed -gt 0) {
        Write-Log "Failed installations:" -Level Warning
        $results.Details | Where-Object { -not $_.Success } | ForEach-Object {
            Write-Log "  - $($_.AppId): $($_.Message) (code: $($_.ExitCode))" -Level Warning
        }
    }

    return $results
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
            'c0re100.qBittorrent-Enhanced-Edition',
            'voidtools.Everything',
            'AntibodySoftware.WizTree',
            'BleachBit.BleachBit',
            'KDE.Krita',
            'EpicGames.EpicGamesLauncher',
            'Nvidia.GeForceNow',
            'Valve.Steam',
            'PrismLauncher.PrismLauncher',
            'RevoUninstaller.RevoUninstaller',
            'ZedIndustries.Zed'
        )

        Install-WingetApps -AppIds $applications

        # Install fonts
        Write-Log "`n--- Installing Fonts ---" -Level Info
        $fonts = @(
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
        }

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
