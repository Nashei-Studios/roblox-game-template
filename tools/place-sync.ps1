#requires -Version 7
<#
.SYNOPSIS
  Keeps the group place on origin/develop: a detached worktree plus a hidden `rojo serve`.
.DESCRIPTION
  pwsh tools/place-sync.ps1 run        fetch, detach the place worktree at origin/develop, start rojo if down
  pwsh tools/place-sync.ps1 install    register a hidden job every 5 minutes (Windows task, cron elsewhere)
  pwsh tools/place-sync.ps1 uninstall  remove that job
  pwsh tools/place-sync.ps1 status     current commit, port and whether rojo listens
  The worktree and port come from .studio.lock at the main checkout, or from -Worktree / -Port.
  See docs/live-vs-branches.md.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet('run', 'install', 'uninstall', 'status')][string]$Command,
    [string]$Worktree,
    [int]$Port,
    [string]$Repo = (Get-Location).Path,
    [string]$Project = 'default.project.json',
    [int]$Minutes = 5
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/place-sync.ps1')

function Get-MainCheckout {
    param([string]$From)
    $common = git -C $From rev-parse --path-format=absolute --git-common-dir
    if ($LASTEXITCODE -ne 0) { throw "Not a git repository: $From" }
    Split-Path -Parent $common
}
function Test-PortListening {
    param([int]$Port)
    $client = [Net.Sockets.TcpClient]::new()
    try { $client.ConnectAsync('127.0.0.1', $Port).Wait(500) -and $client.Connected } catch { $false } finally { $client.Dispose() }
}
function Get-State {
    $main = Get-MainCheckout $Repo
    $lockPath = Join-Path $main '.studio.lock'
    $lock = if (Test-Path -LiteralPath $lockPath) { Read-StudioLock (Get-Content -LiteralPath $lockPath -Raw) } else { $null }
    $wt = $Worktree ? $Worktree : $lock?.worktree
    $pt = $Port ? $Port : $lock?.port
    $exists = [bool]($wt -and (Test-Path -LiteralPath $wt))
    $head = $null; $target = $null
    if ($exists) {
        git -C $wt fetch --quiet origin
        if ($LASTEXITCODE -ne 0) { throw "git fetch failed in $wt" }
        $head = (git -C $wt rev-parse HEAD) 2>$null
        $target = (git -C $wt rev-parse 'origin/develop') 2>$null
    }
    [pscustomobject]@{
        main = $main; lockFound = [bool]$lock; worktree = $wt; port = $pt; worktreeExists = $exists
        head = $head; target = $target; listening = [bool]($pt -and (Test-PortListening $pt))
    }
}
function Start-HiddenRojo {
    param($State)
    $rojo = (Get-Command rojo -ErrorAction Stop).Source
    $rojoArgs = @('serve', $Project, '--port', "$($State.port)")
    if ($IsWindows) { Start-Process -FilePath $rojo -ArgumentList $rojoArgs -WorkingDirectory $State.worktree -WindowStyle Hidden | Out-Null }
    else { Start-Process -FilePath $rojo -ArgumentList $rojoArgs -WorkingDirectory $State.worktree -RedirectStandardOutput /dev/null -RedirectStandardError /dev/null | Out-Null }
}
function Get-SchedulerInvocation {
    $pwshPath = (Get-Process -Id $PID).Path
    [pscustomobject]@{ pwsh = $pwshPath; args = @('-NoProfile', '-File', $PSCommandPath, 'run', '-Repo', (Get-MainCheckout $Repo), '-Project', $Project) }
}

switch ($Command) {
    'run' {
        $state = Get-State
        $plan = Get-PlaceSyncPlan $state
        if (-not $plan.ok) { [Console]::Error.WriteLine("place-sync: $($plan.error)"); exit 1 }
        if ('checkout' -in $plan.actions) {
            git -C $state.worktree checkout --detach --quiet 'origin/develop'
            if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("place-sync: checkout failed in $($state.worktree)"); exit 1 }
            "place-sync: checked out $($state.target.Substring(0, 8))"
        }
        if ('serve' -in $plan.actions) { Start-HiddenRojo $state; "place-sync: rojo serve started on port $($state.port)" }
        if (-not $plan.actions) { 'place-sync: up to date, nothing to do' }
    }
    'status' {
        $s = Get-State
        [ordered]@{
            lock = $s.lockFound; worktree = $s.worktree; port = $s.port
            head = $s.head ? $s.head.Substring(0, 8) : $null; develop = $s.target ? $s.target.Substring(0, 8) : $null
            behind = ($s.head -and $s.target) ? ($s.head -ne $s.target) : $null; rojoListening = $s.listening
        } | ConvertTo-Json
    }
    'install' {
        $inv = Get-SchedulerInvocation; $name = Get-PlaceSyncTaskName (Get-MainCheckout $Repo)
        if ($IsWindows) {
            # conhost --headless runs the console app with no window at all.
            $argLine = "--headless `"$($inv.pwsh)`" " + (($inv.args | ForEach-Object { "`"$_`"" }) -join ' ')
            $action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument $argLine
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $Minutes)
            $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
            Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
            "place-sync: scheduled task '$name' registered every $Minutes min"
        } else {
            $quoted = ($inv.args | ForEach-Object { "'$_'" }) -join ' '
            $line = "*/$Minutes * * * * '$($inv.pwsh)' $quoted # $name"
            $kept = @((crontab -l 2>$null) | Where-Object { $_ -notmatch [regex]::Escape("# $name") })
            (($kept + $line) -join "`n") + "`n" | crontab -
            "place-sync: cron entry '$name' installed"
        }
    }
    'uninstall' {
        $name = Get-PlaceSyncTaskName (Get-MainCheckout $Repo)
        if ($IsWindows) {
            if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $name -Confirm:$false; "place-sync: task '$name' removed" }
            else { "place-sync: no task '$name'" }
        } else {
            $kept = @((crontab -l 2>$null) | Where-Object { $_ -notmatch [regex]::Escape("# $name") })
            ($kept -join "`n") + "`n" | crontab -
            "place-sync: cron entry '$name' removed"
        }
    }
}
