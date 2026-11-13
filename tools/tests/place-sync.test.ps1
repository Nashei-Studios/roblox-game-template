#requires -Version 7
# Unit tests of tools/lib/place-sync.ps1: no git, no processes. Run: pwsh tools/tests/place-sync.test.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib/place-sync.ps1')
$failed = 0
function Assert { param([bool]$Condition, [string]$What) if ($Condition) { "ok    $What" } else { "FAIL  $What"; $script:failed++ } }
function S {
    param($over = @{})
    $b = @{ lockFound = $true; worktree = 'wt'; port = 34872; worktreeExists = $true; head = 'aaa'; target = 'aaa'; listening = $true }
    foreach ($k in $over.Keys) { $b[$k] = $over[$k] }
    [pscustomobject]$b
}

$p = Get-PlaceSyncPlan (S @{ listening = $false })
Assert ($p.ok -and ($p.actions -join ',') -eq 'serve') 'rojo down: starts it'
$p = Get-PlaceSyncPlan (S @{ head = 'old' })
Assert ($p.ok -and ($p.actions -join ',') -eq 'checkout') 'commit behind: checks out'
$p = Get-PlaceSyncPlan (S)
Assert ($p.ok -and $p.actions.Count -eq 0) 'all current: does nothing'
$p = Get-PlaceSyncPlan (S @{ head = 'old'; listening = $false })
Assert (($p.actions -join ',') -eq 'checkout,serve') 'behind and down: checkout first, then serve'
$p = Get-PlaceSyncPlan (S @{ lockFound = $false; worktree = $null; port = $null })
Assert ((-not $p.ok) -and $p.error -match 'No \.studio\.lock') 'no lock: fails with a clear message'
$p = Get-PlaceSyncPlan (S @{ lockFound = $false })
Assert $p.ok 'no lock but explicit worktree and port: works'
$p = Get-PlaceSyncPlan (S @{ port = $null })
Assert ((-not $p.ok) -and $p.error -match 'port') 'lock without port: fails'
$p = Get-PlaceSyncPlan (S @{ worktreeExists = $false })
Assert ((-not $p.ok) -and $p.error -match 'does not exist') 'missing worktree: fails'
$p = Get-PlaceSyncPlan (S @{ target = $null })
Assert (-not $p.ok) 'unresolved origin/develop: fails'

$l = Read-StudioLock "agent=x`nworktree=D:/a/b`nport=34872`n"
Assert ($l.worktree -eq 'D:/a/b' -and $l.port -eq 34872) 'lock parser reads worktree and port'
$l = Read-StudioLock "worktree=/x`r`nport=99999`r`n"
Assert ($l.worktree -eq '/x' -and $null -eq $l.port) 'lock parser rejects an out-of-range port, handles CRLF'
Assert ((Get-PlaceSyncTaskName 'D:\Repos\my game\') -eq 'place-sync-my-game') 'task name is derived from the repo folder'

if ($failed) { "$failed expectation(s) failed"; exit 1 }
'place-sync tests passed'
