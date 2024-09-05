$flags = @{
  "Git.Git"   = "-i"
  "7zip.7zip" = "--force"
}

# List of applications to install via winget
$apps = @(
  "abbodi1406.vcredist",
  "Microsoft.DirectX",
  "Microsoft.XNARedist",
  "OpenAL.OpenAL",
  "Microsoft.WindowsTerminal.Preview",
  "Microsoft.PowerShell.Preview",
  "Git.Git",
  "7zip.7zip",
  "Starship.Starship",
  "chrisant996.Clink",
  "OpenJS.NodeJS",
  "Python.Python.3.12",
  "Oracle.JavaRuntimeEnvironment",
  "Notepad++.Notepad++",
  "sylikc.JPEGView",
  "clsid2.mpc-hc",
  "AntibodySoftware.WizTree",
  "voidtools.Everything.Lite",
  "BleachBit.BleachBit",
  "KDE.Krita",
  "OBSProject.OBSStudio",
  "Skillbrains.Lightshot",
  "RevoUninstaller.RevoUninstaller",
  "EpicGames.EpicGamesLauncher",
  "Valve.Steam",
  "Discord.Discord"
)

# Installing the applications with the appropriate flags
foreach ($app in $apps) {
  $appFlags = $flags[$app]
  if ($appFlags) {
    winget install --id=$app -e $appFlags
  }
  else {
    winget install --id=$app -e
  }
}
