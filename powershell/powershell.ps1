# -------------------------------
# Starship prompt
# -------------------------------
$ENV:STARSHIP_CONFIG = "$HOME\.config\starship.toml"
Invoke-Expression (&starship init powershell)

# -------------------------------
# Custom function to refresh environment
# -------------------------------
function refreshenv {
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
  [System.Environment]::GetEnvironmentVariable("Path", "User")
  Write-Host "Environment refreshed" -ForegroundColor Green
}
