<#
.SYNOPSIS
  Cicha (domyślnie) wersja skryptu instalacyjnego ze Scoop i dotfiles.
.DESCRIPTION
  - Domyślnie wypisuje tylko start, błędy i krótkie podsumowanie.
  - Szczegóły są w pliku log i przy uruchomieniu z -Verbose.
.PARAMETER Force
  Nadpisz istniejące elementy (uwaga: brak backupów, przeznaczone na czysty system).
.PARAMETER DryRun
  Symulacja (nie wykonuje destrukcyjnych operacji).
.PARAMETER DotfilesRepo
  URL repo dotfiles (domyślnie Twój).
#>

[CmdletBinding()]
param(
  [switch]$Force,
  [switch]$DryRun,
  [string]$DotfilesRepo = 'https://github.com/itzL1m4k/.dotfiles.git'
)

# ---------- ustawienia globalne ----------
$LogFile = Join-Path $env:TEMP ("scoop_setup_{0}.log" -f (Get-Date -Format 'yyyyMMddHHmmss'))
function Write-Log { param($msg) $time = (Get-Date).ToString("s"); "$time`t$msg" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

# Minimalny konsolowy output (domyślnie)
Write-Host "Rozpoczynam instalację — log: $LogFile"

Write-Log "START setup script. DryRun=$($DryRun.IsPresent) Force=$($Force.IsPresent) DotfilesRepo=$DotfilesRepo"

# ---------- funkcje ----------
function Test-AdminPrivileges {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
  if (-not $isAdmin) {
    Write-Warning "Brak uprawnień administratora. Niektóre operacje mogą wymagać uprawnień admina."
    Write-Log "Użytkownik nie jest adminem."
    return $false
  }
  Write-Log "Użytkownik ma uprawnienia administratora."
  return $true
}

function Invoke-SafeRun {
  param(
    [Parameter(Mandatory)][string]$Command,
    [string[]]$CmdArgs = @()
  )
  $cmdLine = $Command + " " + ($CmdArgs -join ' ')
  Write-Log "RUN: $cmdLine"

  if ($DryRun) {
    Write-Verbose "DRYRUN: pominięto wykonanie: $cmdLine"
    Write-Log "DRYRUN: $cmdLine"
    return @{ ExitCode = 0; Output = "DRYRUN" }
  }

  try {
    # Chwyć output lokalnie; domyślnie nie echo na konsolę — tylko log i verbose
    $output = & $Command @CmdArgs *>&1 | Out-String
    if ($output) { $output.TrimEnd() | ForEach-Object { Write-Log $_ } }
    $ec = $LASTEXITCODE
    if ($null -eq $ec) { $ec = 0 }
    Write-Verbose ("[{0}] ExitCode={1}" -f $cmdLine, $ec)
    return @{ ExitCode = $ec; Output = $output }
  }
  catch {
    Write-Log "ERROR running $cmdLine : $($_.Exception.Message)"
    Write-Error "Błąd podczas uruchamiania: $cmdLine"
    Write-Verbose $_.Exception.Message
    return @{ ExitCode = 1; Output = $_.Exception.Message }
  }
}

function New-Link {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Target,
    [ValidateSet('Symbolic', 'Hard', 'Junction')][string]$LinkType = 'Symbolic',
    [switch]$ForceLocal
  )

  Write-Log "New-Link: Path='$Path' Target='$Target' Type='$LinkType' Force=$($ForceLocal.IsPresent)"
  Write-Verbose "New-Link called for $Path -> $Target (type $LinkType)"

  if (-not (Test-Path -Path $Target)) {
    Write-Warning "Target nie istnieje: $Target"
    Write-Log "Target not found: $Target"
    return $false
  }

  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path -Path $parent)) {
    if (-not $DryRun) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Write-Log "Created parent: $parent"
    Write-Verbose "Utworzono parent: $parent"
  }

  if (Test-Path -Path $Path) {
    if ($ForceLocal -or $Force) {
      if (-not $DryRun) {
        Remove-Item -Path $Path -Force -Recurse -ErrorAction SilentlyContinue
        Write-Log "Removed existing item: $Path"
        Write-Verbose "Usunięto: $Path"
      }
      else {
        Write-Verbose "DRYRUN: Remove $Path"
      }
    }
    else {
      Write-Warning "Element istnieje: $Path (użyj -Force by nadpisać)"
      Write-Log "Element exists and not forced: $Path"
      return $false
    }
  }

  if ($DryRun) {
    Write-Verbose "DRYRUN: create link $Path -> $Target (type $LinkType)"
    return $true
  }

  try {
    if ($LinkType -eq 'Junction') {
      Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "mklink", "/J", "`"$Path`"", "`"$Target`"" -NoNewWindow -Wait
    }
    elseif ($LinkType -eq 'Hard') {
      New-Item -ItemType HardLink -Path $Path -Target $Target -Force | Out-Null
    }
    else {
      if ((Get-Item $Target).PSIsContainer) {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "mklink", "/J", "`"$Path`"", "`"$Target`"" -NoNewWindow -Wait
      }
      else {
        New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force | Out-Null
      }
    }
    Write-Log "Link created: $Path -> $Target"
    Write-Verbose "Link created: $Path -> $Target"
    return $true
  }
  catch {
    Write-Warning "Błąd tworzenia linku: $($_.Exception.Message)"
    Write-Log "ERROR New-Link: $($_.Exception.Message)"
    return $false
  }
}

function Install-Scoop {
  Write-Log "Install-Scoop start"
  Write-Verbose "Sprawdzam instalację Scoop..."

  if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Verbose "Scoop już zainstalowany."
    Write-Log "Scoop already installed"
    return $true
  }

  if ($DryRun) {
    Write-Log "DRYRUN: pominięto instalację scoop"
    Write-Verbose "DRYRUN: install scoop"
    return $true
  }

  try {
    $installer = Join-Path $env:TEMP "get-scoop.ps1"
    Invoke-WebRequest -UseBasicParsing -Uri "https://get.scoop.sh" -OutFile $installer -ErrorAction Stop
    Write-Log "Pobrano instalator: $installer"

    # Uruchom bez echo na konsoli; output i tak zostanie zalogowany
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installer | Out-Null
    $ec = $LASTEXITCODE
    Write-Log "Installer exit code: $ec"
    Remove-Item $installer -Force -ErrorAction SilentlyContinue

    $shims = Join-Path $env:USERPROFILE "scoop\shims"
    if (Test-Path $shims -and ($env:Path -notlike "*$shims*")) {
      $env:Path = $env:Path + ";" + $shims
      Write-Log "Added shims to PATH"
    }

    if (Get-Command scoop -ErrorAction SilentlyContinue) {
      Write-Verbose "Scoop zainstalowany."
      Write-Log "Scoop installed success"
      return $true
    }
    else {
      Write-Error "Instalacja Scoop nie powiodła się (komenda scoop nieznaleziona). Sprawdź log."
      Write-Log "Scoop not found after install"
      return $false
    }
  }
  catch {
    Write-Error "Błąd instalacji Scoop: $($_.Exception.Message)"
    Write-Log "ERROR Install-Scoop: $($_.Exception.Message)"
    return $false
  }
}

function Add-ScoopBuckets {
  Write-Log "Add-ScoopBuckets start"
  Write-Verbose "Dodaję bucket'y Scoop..."

  $buckets = @('extras', 'games', 'java', 'nerd-fonts')
  $successCount = 0

  foreach ($bucket in $buckets) {
    Write-Verbose "Adding bucket: $bucket"
    $res = Invoke-SafeRun -Command "scoop" -CmdArgs @("bucket", "add", $bucket)
    if ($res.ExitCode -eq 0) { $successCount++ } else { Write-Log "Failed adding bucket $bucket (code $($res.ExitCode))" }
  }

  Write-Log "Add-ScoopBuckets done: $successCount/$($buckets.Count)"
}

function Install-ScoopApps {
  param([array]$apps)
  Write-Log "Install-ScoopApps start. Count: $($apps.Count)"
  Write-Verbose "Instalowanie aplikacji (szczegóły w log lub -Verbose)."

  $successCount = 0
  $failed = @()

  foreach ($app in $apps) {
    $pkg = if ($app -is [string]) { $app } else { $app.name }
    $argList = @("install", $pkg)
    Write-Verbose "Installing $pkg"
    $res = Invoke-SafeRun -Command "scoop" -CmdArgs $argList
    if ($res.ExitCode -eq 0) { $successCount++ } else { $failed += $pkg; Write-Log "Failed install $pkg (code $($res.ExitCode))" }
  }

  # Podsumowanie: pokaż minimalnie (tylko jeśli coś nie poszło lub w trybie verbose)
  if ($failed.Count -gt 0) {
    Write-Warning ("Nie udało się zainstalować: {0}" -f ($failed -join ", "))
  }
  else {
    Write-Verbose ("Wszystkie aplikacje zainstalowane: $successCount/$($apps.Count)")
  }

  Write-Log "Install-ScoopApps done: success $successCount failed $($failed.Count)"
  return @{ Success = $successCount; Failed = $failed }
}

function Test-GitAvailability {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warning "Git nie jest dostępny w PATH."
    Write-Log "Git not available"
    return $false
  }
  Write-Log "Git available"
  return $true
}

function Set-DotfilesConfiguration {
  Write-Log "Set-DotfilesConfiguration start"
  Write-Verbose "Konfiguracja dotfiles (szczegóły w log)."

  if (-not (Test-GitAvailability)) { return $false }

  $dotfilesPath = Join-Path $env:USERPROFILE ".dotfiles"

  if (Test-Path -Path $dotfilesPath) {
    if (-not $DryRun) { Remove-Item -Path $dotfilesPath -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Log "Removed existing dotfiles (no backups per request)."
  }

  if (-not $DryRun) {
    try {
      git clone --depth 1 $DotfilesRepo $dotfilesPath 2>&1 | ForEach-Object { Write-Log $_ }
      if (-not (Test-Path -Path $dotfilesPath)) { Write-Log "Clone failed"; return $false }
      Write-Log "Dotfiles cloned"
    }
    catch {
      Write-Log "ERROR clone dotfiles: $($_.Exception.Message)"
      return $false
    }
  }
  else {
    Write-Log "DRYRUN: clone dotfiles skipped"
  }

  # Linki (na czystym systemie bez backupów)
  $links = @(
    @{ Path = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'; Target = Join-Path $dotfilesPath 'terminal\settings.json'; Type = 'Symbolic' },
    @{ Path = Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'; Target = Join-Path $dotfilesPath 'powershell\powershell.ps1'; Type = 'Symbolic' },
    @{ Path = Join-Path $env:USERPROFILE 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'; Target = Join-Path $dotfilesPath 'powershell\powershell.ps1'; Type = 'Symbolic' },
    @{ Path = Join-Path $env:APPDATA 'Notepad++\themes\catppuccin-mocha.xml'; Target = Join-Path $dotfilesPath 'notepad\catppuccin-mocha.xml'; Type = 'Symbolic' },
    @{ Path = Join-Path $env:USERPROFILE '.config\starship.toml'; Target = Join-Path $dotfilesPath '.config\starship.toml'; Type = 'Symbolic' },
    @{ Path = Join-Path $env:LOCALAPPDATA 'clink\starship.lua'; Target = Join-Path $dotfilesPath 'clink\starship.lua'; Type = 'Symbolic' },
    @{ Path = Join-Path $env:USERPROFILE '.bash_profile'; Target = Join-Path $dotfilesPath '.bash_profile'; Type = 'Symbolic' },
    @{ Path = Join-Path $env:USERPROFILE '.gitconfig'; Target = Join-Path $dotfilesPath '.gitconfig'; Type = 'Symbolic' }
  )

  $created = 0
  foreach ($l in $links) {
    $linkType = $l.Type
    if ((Test-Path $l.Target) -and (Get-Item $l.Target).PSIsContainer) { $linkType = 'Junction' }
    if (New-Link -Path $l.Path -Target $l.Target -LinkType $linkType -ForceLocal:$Force) { $created++ }
  }

  Write-Log "Set-DotfilesConfiguration done. Links created: $created/$($links.Count)"

  $regPath = Join-Path $dotfilesPath "registry\registry.reg"
  if (Test-Path -Path $regPath -and -not $DryRun) {
    try { Start-Process -FilePath "reg.exe" -ArgumentList "import", "`"$regPath`"" -Wait -NoNewWindow; Write-Log "Registry imported" } catch { Write-Log "Failed import registry: $($_.Exception.Message)" }
  }

  return $true
}

# ---------- główna logika ----------
function Invoke-Setup {
  $start = Get-Date
  Write-Log "Invoke-Setup start at $start"
  Write-Verbose "Starting setup"

  $isAdmin = Test-AdminPrivileges
  if (-not $isAdmin) { Write-Verbose "Installing per-user (non-admin) mode." }

  if (-not (Install-Scoop)) {
    Write-Error "Nie udało się zainstalować Scoop. Sprawdź log: $LogFile"
    Write-Log "Abort: Scoop installation failed"
    return 1
  }

  Add-ScoopBuckets

  $scoopApps = @(
    @{ name = "extras/vcredist-aio" },
    @{ name = "main/7zip" },
    @{ name = "main/git" },
    @{ name = "main/pwsh" },
    @{ name = "main/starship" },
    @{ name = "main/clink" },
    @{ name = "main/nodejs" },
    @{ name = "main/fastfetch" },
    @{ name = "main/python" },
    @{ name = "main/adb" },
    @{ name = "main/cmake" },
    @{ name = "main/mingw" },
    @{ name = "main/curl" },
    @{ name = "main/wget" },
    @{ name = "main/ripgrep" },
    @{ name = "main/fd" },
    @{ name = "main/fzf" },
    @{ name = "java/openjdk" },
    @{ name = "extras/brave" },
    @{ name = "extras/discord" },
    @{ name = "extras/windows-terminal" },
    @{ name = "extras/notepadplusplus" },
    @{ name = "extras/vscode" },
    @{ name = "extras/vlc" },
    @{ name = "extras/nomacs" },
    @{ name = "extras/obs-studio" },
    @{ name = "extras/qbittorrent-enhanced" },
    @{ name = "extras/spotify" },
    @{ name = "extras/everything" },
    @{ name = "extras/wiztree" },
    @{ name = "extras/sysinternals" },
    @{ name = "extras/hwinfo" },
    @{ name = "extras/bleachbit" },
    @{ name = "extras/equalizer-apo" },
    @{ name = "extras/krita" },
    @{ name = "extras/epicgameslauncher" },
    @{ name = "extras/geforce-now" },
    @{ name = "games/steam" },
    @{ name = "nerd-fonts/FiraCode" },
    @{ name = "nerd-fonts/Cascadia-Code" }
  )

  $installResult = Install-ScoopApps -apps $scoopApps

  # odśwież PATH tylko w sesji
  $scoopShims = Join-Path $env:USERPROFILE "scoop\shims"
  if ((Test-Path $scoopShims) -and ($env:Path -notlike "*$scoopShims*")) {
    $env:Path = $env:Path + ";" + $scoopShims
    Write-Log "Updated PATH to include scoop shims"
  }

  if (-not (Set-DotfilesConfiguration)) {
    Write-Warning "Konfiguracja dotfiles nie powiodła się. Zobacz log."
    Write-Log "Dotfiles config failed"
  }

  $end = Get-Date
  $dur = $end - $start

  # Minimalne podsumowanie
  if ($installResult.Failed.Count -gt 0) {
    Write-Warning ("Instalacja zakończona, niektóre pakiety się nie zainstalowały: {0}" -f ($installResult.Failed -join ", "))
  }
  else {
    Write-Host "Instalacja zakończona pomyślnie." -ForegroundColor Green
  }

  Write-Host "Czas: $($dur.ToString('hh\:mm\:ss')). Log: $LogFile"
  Write-Log "Invoke-Setup finished at $end duration $($dur.ToString())"

  return 0
}

# ---------- uruchomienie ----------
$exitCode = Invoke-Setup
Write-Log "Script exit code: $exitCode"
exit $exitCode
