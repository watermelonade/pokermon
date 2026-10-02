<#
.SYNOPSIS
  Starts A Friend in Need from a checkout: re-imports, then runs the game.

.DESCRIPTION
  What the right-click entry from install_context_menu.ps1 runs. The import
  comes first because Godot only sees a new class_name script after one,
  so a launch straight after `git pull` would otherwise fail with
  "Identifier not declared". It takes a few seconds and changes nothing
  when there's nothing new.

  The import runs with -NoNewWindow inside the launcher's own hidden
  PowerShell window, so nothing flashes up: Windows PowerShell 5.1 won't
  reliably combine -WindowStyle with redirected output.

  If the import fails, a message box says so and points at the log
  (%TEMP%\AFriendInNeed-import.log) instead of failing silently.
#>
param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [Parameter(Mandatory = $true)][string]$Project
)

$log = Join-Path $env:TEMP "AFriendInNeed-import.log"

function Show-Problem([string]$text) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($text, "A Friend in Need") | Out-Null
}

if (-not (Test-Path -LiteralPath $Godot)) {
    Show-Problem "Godot isn't at '$Godot' any more. Run scripts\windows\install_context_menu.ps1 again."
    exit 1
}
if (-not (Test-Path -LiteralPath (Join-Path $Project "project.godot"))) {
    Show-Problem "The game isn't at '$Project' any more. Run scripts\windows\install_context_menu.ps1 again from the checkout."
    exit 1
}

$import = Start-Process -FilePath $Godot -ArgumentList @("--headless", "--path", "`"$Project`"", "--import") `
    -NoNewWindow -Wait -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
if ($import.ExitCode -ne 0) {
    Show-Problem "Godot couldn't import the project (exit code $($import.ExitCode)). The log is at $log"
    exit 1
}

Start-Process -FilePath $Godot -ArgumentList @("--path", "`"$Project`"")
