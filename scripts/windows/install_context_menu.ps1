<#
.SYNOPSIS
  Adds "Play A Friend in Need" to the Windows right-click menu.

.DESCRIPTION
  Right-click the desktop (or, with -Everywhere, the empty space in any
  folder) and pick "Play A Friend in Need" to start the game from this
  checkout with Godot. On Windows 11 the entry is under "Show more options"
  (or Shift+F10), where Windows puts every classic menu entry.

  The entry runs scripts\windows\launch_game.ps1, which re-imports the
  project first (a few seconds) and then starts the game. The import is
  what keeps a fresh `git pull` working: Godot can't see a new class_name
  script until the project is re-imported ("Identifier not declared").

  Everything goes under HKEY_CURRENT_USER, so no admin rights are needed
  and nothing changes for other accounts. -Uninstall removes it again.

  Run it from PowerShell in the checkout:
    powershell -ExecutionPolicy Bypass -File scripts\windows\install_context_menu.ps1
  or right-click this file and pick "Run with PowerShell".

.PARAMETER Godot
  Path to the Godot 4.7.2 editor exe (Godot_v4.7.2-stable_win64.exe). If
  left out, the script looks in the usual places and, failing that, asks
  you to pick it in a file dialog.

.PARAMETER Project
  The game's folder (the one with project.godot). Defaults to this
  checkout.

.PARAMETER Everywhere
  Also add the entry to every folder's background menu, not just the
  desktop's.

.PARAMETER Uninstall
  Remove the menu entries.
#>
param(
    [string]$Godot = "",
    [string]$Project = "",
    [switch]$Everywhere,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$Name = "AFriendInNeed"
$Label = "Play A Friend in Need"
$Keys = @(
    "HKCU:\Software\Classes\DesktopBackground\Shell\$Name",   # right-click the desktop
    "HKCU:\Software\Classes\Directory\Background\shell\$Name" # right-click inside any folder
)

if ($Uninstall) {
    foreach ($key in $Keys) {
        if (Test-Path -LiteralPath $key) {
            Remove-Item -LiteralPath $key -Recurse -Force
            Write-Host "Removed $key"
        }
    }
    Write-Host "The menu entry is gone."
    exit 0
}

# The game's folder: this script lives in <checkout>\scripts\windows.
if (-not $Project) {
    $Project = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
if (-not (Test-Path -LiteralPath (Join-Path $Project "project.godot"))) {
    throw "No project.godot in '$Project'. Pass -Project <the game's folder>."
}

# Godot: the -Godot argument, then $env:GODOT, then PATH, then the usual
# download and install spots, newest 4.7 first; the console exe is skipped
# (it opens a black window next to the game).
function Find-Godot {
    if ($env:GODOT -and (Test-Path -LiteralPath $env:GODOT)) { return $env:GODOT }
    foreach ($cmd in @("godot", "godot4", "Godot_v4.7.2-stable_win64")) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) { return $found.Source }
    }
    $places = @(
        "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents",
        "$env:USERPROFILE\Godot", "$env:LOCALAPPDATA\Programs", "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}\Steam\steamapps\common\Godot Engine",
        "$env:USERPROFILE\scoop\apps\godot\current", "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
    )
    $candidates = foreach ($place in $places) {
        if ($place -and (Test-Path -LiteralPath $place)) {
            Get-ChildItem -LiteralPath $place -Recurse -Depth 3 -Filter "*odot*.exe" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch "console" }
        }
    }
    $best = $candidates | Sort-Object @{ Expression = { $_.Name -match "4\.7" }; Descending = $true },
            @{ Expression = { $_.LastWriteTime }; Descending = $true } |
        Select-Object -First 1
    if ($best) { return $best.FullName }
    return $null
}

if (-not $Godot) { $Godot = Find-Godot }
if (-not $Godot) {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Where is Godot 4.7.2? (Godot_v4.7.2-stable_win64.exe)"
    $dialog.Filter = "Godot (*.exe)|*.exe"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $Godot = $dialog.FileName }
}
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot)) {
    throw "Couldn't find Godot. Download Godot 4.7.2 (Windows, 64-bit) from godotengine.org and pass -Godot <path to the exe>."
}
$Godot = (Resolve-Path -LiteralPath $Godot).Path
if ($Godot -notmatch "4\.7") {
    Write-Warning "'$Godot' doesn't look like Godot 4.7. The game is made for 4.7.2; another version may not open it."
}

$launcher = Join-Path $PSScriptRoot "launch_game.ps1"
$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`" -Godot `"$Godot`" -Project `"$Project`""

$targets = if ($Everywhere) { $Keys } else { @($Keys[0]) }
foreach ($key in $targets) {
    New-Item -Path $key -Force | Out-Null
    Set-ItemProperty -LiteralPath $key -Name "(default)" -Value $Label
    Set-ItemProperty -LiteralPath $key -Name "Icon" -Value "`"$Godot`",0"
    New-Item -Path "$key\command" -Force | Out-Null
    Set-ItemProperty -LiteralPath "$key\command" -Name "(default)" -Value $command
    Write-Host "Added $key"
}
Write-Host ""
Write-Host "Done. Right-click the desktop and pick '$Label'."
Write-Host "(Windows 11: it's under 'Show more options', or press Shift+F10.)"
Write-Host "Godot:   $Godot"
Write-Host "Project: $Project"
Write-Host "To remove it: powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Uninstall"
