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

# Git Bash, in order of preference: an explicit override, the portable Git
# bundled under DSH_HOME, a normal Git for Windows install, then PATH.
$candidates = @(
    $env:DSH_GIT_BASH,
    $(if ($env:DSH_HOME) { Join-Path $env:DSH_HOME "tools\PortableGit\bin\bash.exe" }),
    (Join-Path $env:ProgramFiles "Git\bin\bash.exe"),
    $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} "Git\bin\bash.exe" }),
    (Join-Path $env:LOCALAPPDATA "Programs\Git\bin\bash.exe")
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$bash = $candidates | Select-Object -First 1
if (-not $bash) {
    $onPath = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($onPath) { $bash = $onPath.Source }
}
if (-not $bash) {
    throw "Git Bash not found. Set DSH_GIT_BASH, or install Git for Windows (https://git-scm.com/download/win)."
}

# Git Bash wants forward slashes; single quotes keep spaces in the path safe.
$scriptForBash = $script -replace '\\', '/'
$profileForBash = $profileDir -replace '\\', '/'
# DSH_SYNC_PROFILE is passed inline: the task does not inherit the session
# environment, so DSH_HOME may be absent when the task fires.
$arguments = "-lc `"DSH_SYNC_PROFILE='$profileForBash' '$scriptForBash' sync`""

# The task starts bash in the profile directory so git never picks up a
# different repository from the inherited working directory.
$action = New-ScheduledTaskAction -Execute $bash -Argument $arguments -WorkingDirectory $profileDir
$atLogon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
# No -RepetitionDuration: [TimeSpan]::MaxValue serialises to P99999999DT23H59M59S,
# which the Task Scheduler service rejects with 0x80041318. Omitting it means
# "repeat indefinitely", which is what we want anyway.
$every = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($atLogon, $every) `
    -Settings $settings -Description "Commit and push the DSH profile to its git remote." -Force `
    -ErrorAction Stop | Out-Null

Write-Host "registered scheduled task '$TaskName' every $IntervalMinutes minutes"
Write-Host "run it now:  schtasks /run /tn `"$TaskName`""
Write-Host "check it:    bash -lc `"'$scriptForBash' status`""
Write-Host ""
Write-Host "First push needs credentials. Either the remote uses SSH and the key is"
Write-Host "already loaded (recommended here), or run this once in Git Bash:"
Write-Host "  cd `"$profileForBash`" && git push"
Write-Host "and satisfy the credential prompt it shows."
