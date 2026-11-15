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

$none = { param($p) $false }
$all = { param($p) $true }
Assert ((Resolve-StablePwshPath -Current 'C:/WindowsApps/Microsoft.PowerShell_7.7.0.0_x64/pwsh.exe' -LocalAppData 'C:\Users\u\AppData\Local' -Exists $all) -eq 'C:/Users/u/AppData/Local/Microsoft/WindowsApps/pwsh.exe') 'pwsh: the stable alias wins when it exists'
Assert ((Resolve-StablePwshPath -Current '/usr/bin/pwsh' -LocalAppData 'C:/x' -Exists $none) -eq '/usr/bin/pwsh') 'pwsh: falls back to the running executable'
Assert ((Resolve-StablePwshPath -Current '/usr/bin/pwsh' -Exists $all) -eq '/usr/bin/pwsh') 'pwsh: no LOCALAPPDATA keeps the running executable'
$arg = '--headless "C:/old/pwsh.exe" "-NoProfile" "-File" "x.ps1"'
Assert ((Get-TaskExecutablePath $arg) -eq 'C:/old/pwsh.exe') 'task argument: pwsh path is extracted'
Assert ($null -eq (Get-TaskExecutablePath 'nothing here')) 'task argument: unknown shape gives null'
Assert ($null -eq (Get-TaskHealth $null $none)) 'task health: not registered is not a warning'
Assert ($null -eq (Get-TaskHealth $arg $all)) 'task health: existing executable is fine'
Assert ((Get-TaskHealth $arg $none) -match 'no longer exists') 'task health: warns when the executable is gone'
Assert ((Get-TaskHealth 'garbage' $all) -match 'unrecognised') 'task health: warns on an unrecognised command line'

if ($failed) { "$failed expectation(s) failed"; exit 1 }
'place-sync tests passed'
