# Sprawdzenie uprawnień administratora
function Test-AdminPrivileges {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
  if (-not $isAdmin) {
    Write-Error "Ten skrypt musi być uruchomiony z uprawnieniami administratora. Uruchom PowerShell jako administrator i spróbuj ponownie."
    exit 1
  }
}

# Funkcja do instalacji programów z linków
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

function Main {
  Test-AdminPrivileges

  $wingetApps = @(
    @{name="abbodi1406.vcredist"},
    @{name="Microsoft.DirectX"},
    @{name="7zip.7zip"},
    @{name="Git.Git"},
    @{name="Notepad++.Notepad++"},
    @{name="Orwell.Dev-C++"},
    @{name="Codeblocks.Codeblocks"},
    @{name="OpenJS.NodeJS.LTS"},
    @{name="Google.Chrome"},
    @{name="Oracle.JDK.23"},
    @{name="GIMP.GIMP"},
    @{name="ApacheFriends.Xampp.8.2"},
    @{name="JetBrains.IntelliJIDEA.Community"},
    @{name="Google.AndroidStudio"},
    @{name="Microsoft.VisualStudio.2022.Community"},
  )

  Install-WingetApps -apps $wingetApps

  Install-Programs -tempPath "$env:TEMP\VSCodeSetup-x64.exe" -url "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64"
  Install-Programs -tempPath "$env:TEMP\inkscape.msi" -url "https://inkscape.org/gallery/item/53697/inkscape-1.4_2024-10-11_86a8ad7-x64.msi"
  Install-Programs -tempPath "$env:TEMP\clear.bat" -url "https://raw.githubusercontent.com/itzL1m4k/.dotfiles/refs/heads/main/clear.bat"

  $url = "https://raw.githubusercontent.com/itzL1m4k/.dotfiles/refs/heads/main/clear.bat"
  $tempPath = "$env:TEMP\clear.bat"

  Invoke-WebRequest -Uri $url -OutFile $tempPath -UseBasicParsing -ErrorAction Stop

  cd "$env:TEMP"
  ./clear.bat
}