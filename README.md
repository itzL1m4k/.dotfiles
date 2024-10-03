## 1. First install chocolatey on your windows system, in your powershell as administrator paste the command below:

```powershell
Set-ExecutionPolicy Bypass -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

## 2. It is recommended to restart your powershell

## 3. Now you can run installScript in your powershell as administrator

```powershell
Set-ExecutionPolicy Bypass -Force; iwr -useb https://raw.githubusercontent.com/itzL1m4k/.dotfiles/main/installScript.ps1 | iex
```
