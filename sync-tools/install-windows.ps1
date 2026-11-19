# Register a Windows scheduled task that runs "dsh-sync sync" every N minutes.
#
#   powershell -ExecutionPolicy Bypass -File sync-tools\install-windows.ps1
#   powershell -ExecutionPolicy Bypass -File sync-tools\install-windows.ps1 -IntervalMinutes 30
#   powershell -ExecutionPolicy Bypass -File sync-tools\install-windows.ps1 -Uninstall
#
# The task runs Git Bash, so it needs Git for Windows. Runs as the current user;
# no administrator shell required.
[CmdletBinding()]
param(
    [int]$IntervalMinutes = 15,
    [string]$TaskName = "DSH profile sync",
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "removed scheduled task: $TaskName"
    exit 0
}

$profileDir = Split-Path -Parent $PSScriptRoot
$script = Join-Path $profileDir "sync-tools\dsh-sync.sh"
if (-not (Test-Path -LiteralPath $script)) {
    throw "dsh-sync.sh not found at $script"
}
if (-not (Test-Path -LiteralPath (Join-Path $profileDir ".git"))) {
    throw "$profileDir is not a git repository"
}

$candidates = @(
    (Join-Path $env:ProgramFiles "Git\bin\bash.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Git\bin\bash.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\Git\bin\bash.exe")
)
$bash = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $bash) {
    throw "Git Bash not found. Install Git for Windows first (https://git-scm.com/download/win)."
}

# Git Bash wants forward slashes and a quoted path.
$scriptForBash = $script -replace '\\', '/'
$arguments = "-lc `"`"$scriptForBash`" sync`""

$action = New-ScheduledTaskAction -Execute $bash -Argument $arguments
$atLogon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$every = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
    -RepetitionDuration ([TimeSpan]::MaxValue)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($atLogon, $every) `
    -Settings $settings -Description "Commit and push the DSH profile to its git remote." -Force | Out-Null

Write-Host "registered scheduled task '$TaskName' every $IntervalMinutes minutes"
Write-Host "run it now:  schtasks /run /tn `"$TaskName`""
Write-Host "check it:    bash `"$scriptForBash`" status"
Write-Host ""
Write-Host "First push needs credentials: open Git Bash and run"
Write-Host "  cd ~/.dsh/profiles/desktop && git push"
Write-Host "Git Credential Manager opens a browser once, then keeps the token."
