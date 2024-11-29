# Windows Development Environment Setup

> Skrypt automatyzujący instalację środowiska deweloperskiego na Windows

## Wymagania wstępne

- Windows 10 lub nowszy
- PowerShell 5.1 lub nowszy
- Uprawnienia administratora

## Instrukcja instalacji

### 1. Instalacja Chocolatey

Uruchom PowerShell jako administrator i wykonaj poniższe polecenie:

```powershell
Set-ExecutionPolicy Bypass -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

### 2. Konfiguracja Chocolatey

Zrestartuj PowerShell i zaimportuj moduł Chocolatey:

```powershell
Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1
```

### 3. Uruchomienie skryptu instalacyjnego

Wykonaj poniższe polecenie w PowerShell (jako administrator):

```powershell
Set-ExecutionPolicy Bypass -Force; iwr -useb https://raw.githubusercontent.com/itzL1m4k/.dotfiles/main/installScript.ps1 | iex
```

## Rozwiązywanie problemów

- Jeśli występuje błąd ExecutionPolicy, upewnij się, że PowerShell jest uruchomiony jako administrator
- W przypadku problemów z połączeniem, sprawdź swoje połączenie internetowe
- Szczegółowe logi instalacji można znaleźć w: `%TEMP%\chocolatey`
