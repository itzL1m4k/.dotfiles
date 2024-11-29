# Sprawdzenie uprawnień administratora
function Test-AdminPrivileges {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if (-not $isAdmin) {
        Write-Error "Ten skrypt musi być uruchomiony z uprawnieniami administratora. Uruchom PowerShell jako administrator i spróbuj ponownie."
        exit 1
    }
}

# Funkcja do instalacji programów z linków (bez zmian)
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

# Funkcja do tworzenia dowiązań symbolicznych (bez zmian)
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

# Funkcja do instalacji aplikacji przez Winget
function Install-WingetApps {
    param (
        [array]$apps
    )
    foreach ($app in $apps) {
        if ($app.params) {
            Write-Host "Instalowanie $($app.name) z parametrami: $($app.params)"
            winget install -e --id $app.name $app.params
        } else {
            Write-Host "Instalowanie $($app.name)"
            winget install -e --id $app.name
        }
    }
}

# Funkcja do instalacji aplikacji przez Chocolatey
function Install-ChocolateyApps {
    param (
        [array]$apps
    )
    choco feature enable -n allowGlobalConfirmation
    foreach ($app in $apps) {
        Write-Host "Instalowanie $($app.name) przez Chocolatey"
        choco install $app.name
    }
    choco-cleaner
}

# Funkcja do instalacji aplikacji użytkownika (bez uprawnień administratora)
function Install-UserApps {
    $commands = @(
        "winget install -e --id Nvidia.GeForceNow",
        "winget install -e --id Spotify.Spotify",
        "iwr -useb https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.ps1 | iex"
    )
    $commandString = $commands -join " ; "
    runas /user:$env:USERNAME "powershell.exe -NoProfile $commandString"
}

# Funkcja do konfiguracji dotfiles
function Set-DotfilesConfiguration {
    $dotfilesPath = "$env:USERPROFILE\.dotfiles"

    if (Test-Path -Path $dotfilesPath) {
        Remove-Item -Path $dotfilesPath -Recurse -Force
        Write-Host "Katalog '$dotfilesPath' usunięty."
    }

    git clone https://github.com/itzL1m4k/.dotfiles.git $dotfilesPath

    # Tworzenie dowiązań symbolicznych
    $links = @(
        @{Path="$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"; Target="$dotfilesPath\terminal\settings.json"},
        @{Path="$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"; Target="$dotfilesPath\powershell\powershell.ps1"},
        @{Path="$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"; Target="$dotfilesPath\powershell\powershell.ps1"},
        @{Path="$env:APPDATA\Notepad++\themes\catppuccin-mocha.xml"; Target="$dotfilesPath\notepad\catppuccin-mocha.xml"},
        @{Path="$env:USERPROFILE\.config\starship.toml"; Target="$dotfilesPath\.config\starship.toml"},
        @{Path="$env:LOCALAPPDATA\clink\starship.lua"; Target="$dotfilesPath\clink\starship.lua"},
        @{Path="$env:USERPROFILE\.bash_profile"; Target="$dotfilesPath\.bash_profile"},
        @{Path="$env:USERPROFILE\.gitconfig"; Target="$dotfilesPath\.gitconfig"}
    )

    foreach ($link in $links) {
        New-Link -Path $link.Path -Target $link.Target -LinkType "Symbolic" -Force
    }

    # Import rejestru
    Start-Process -FilePath "reg.exe" -ArgumentList "import", "C:\Users\$env:USERNAME\.dotfiles\registry\registry.reg" -Verb RunAs
}

# Główna funkcja
function Main {
    Test-AdminPrivileges

    $wingetApps = @(
        @{name="Fastfetch-cli.Fastfetch"},
        @{name="ajeetdsouza.zoxide"},
        @{name="junegunn.fzf"},
        @{name="Git.Git"; params="-i"},
        @{name="7zip.7zip"; params="--force"},
        @{name="Brave.Brave"},
        @{name="Microsoft.WindowsTerminal.Preview"},
        @{name="Microsoft.PowerShell"},
        @{name="Starship.Starship"},
        @{name="chrisant996.Clink"},
        @{name="OpenJS.NodeJS"},
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
        @{name="c0re100.qBittorrent-Enhanced-Edition"},
        @{name="EpicGames.EpicGamesLauncher"},
        @{name="Discord.Discord"},
        @{name="Valve.Steam"},
        @{name="9P8LTPGCBZXD"}

        # @{name="Google.AndroidStudio"},
        # @{name="Microsoft.VisualStudio.2022.Community"},

    )

    $chocoApps = @(
        @{name="equalizerapo"},
        @{name="choco-cleaner"}
    )

    Install-WingetApps -apps $wingetApps
    Install-ChocolateyApps -apps $chocoApps

    # Instalacja bun.sh
    if (!(Get-Command bun -ErrorAction SilentlyContinue) -or !(Get-Command bunx -ErrorAction SilentlyContinue)) {
        irm bun.sh/install.ps1 | iex
    }

    refreshenv

    Install-UserApps

    refreshenv

    # Instalacja dodatkowych programów
    Install-Programs -tempPath "$env:TEMP\VencordInstaller.exe" -url "https://github.com/Vencord/Installer/releases/latest/download/VencordInstaller.exe"
    Install-Programs -tempPath "$env:TEMP\VSCodeSetup-x64.exe" -url "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64"

    Set-DotfilesConfiguration
}

# Uruchomienie skryptu
Main
