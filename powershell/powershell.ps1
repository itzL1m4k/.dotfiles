# -------------------------------
# Starship prompt
# -------------------------------
$ENV:STARSHIP_CONFIG = "$HOME\.config\starship.toml"
Invoke-Expression (&starship init powershell)

# -------------------------------
# Import PSReadLine and posh-git from Scoop
# -------------------------------
Import-Module PSReadLine
Import-Module posh-git

# PSReadLine options
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -Colors @{
  Command   = [ConsoleColor]::Cyan
  Parameter = [ConsoleColor]::Yellow
  String    = [ConsoleColor]::Green
  Variable  = [ConsoleColor]::Magenta
  Comment   = [ConsoleColor]::DarkGray
}

# -------------------------------
# Custom function to refresh environment
# -------------------------------
function refreshenv {
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
  [System.Environment]::GetEnvironmentVariable("Path", "User")
  Write-Host "Environment refreshed" -ForegroundColor Green
}
