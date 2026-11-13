#requires -Version 7
# Pure helpers for tools/place-sync.ps1: no network, no git, no processes, so they are unit-tested by
# tools/tests/place-sync.test.ps1. The worktree and the port always come from .studio.lock or parameters.

function Read-StudioLock {
    <# Parses the key=value body of .studio.lock. Returns worktree and port (nulls when absent or invalid). #>
    param([string]$Body)
    $worktree = $null; $port = $null
    foreach ($line in ($Body -split "\r?\n")) {
        if ($line -match '^\s*worktree\s*=\s*(.+?)\s*$') { $worktree = $Matches[1] }
        elseif ($line -match '^\s*port\s*=\s*(\d{1,5})\s*$' -and [int]$Matches[1] -in 1..65535) { $port = [int]$Matches[1] }
    }
    [pscustomobject]@{ worktree = $worktree; port = $port }
}

function Get-PlaceSyncPlan {
    <#
    Decides what one `run` must do. State fields: lockFound, worktree, port, worktreeExists,
    head (sha of the worktree), target (sha of origin/develop), listening (is rojo serving the port).
    Returns { ok, error, actions } where actions is an ordered subset of 'checkout', 'serve'.
    #>
    param([Parameter(Mandatory)]$State)
    $fail = { param($m) [pscustomobject]@{ ok = $false; error = $m; actions = @() } }
    if (-not $State.worktree -and -not $State.lockFound) {
        return & $fail 'No .studio.lock found and no -Worktree given. Create the lock (docs/multi-agent.md) or pass -Worktree and -Port.'
    }
    if (-not $State.worktree) { return & $fail '.studio.lock has no worktree= line and no -Worktree was given.' }
    if (-not $State.port) { return & $fail '.studio.lock has no valid port= line and no -Port was given.' }
    if (-not $State.worktreeExists) { return & $fail "The place worktree does not exist: $($State.worktree). Create it detached at origin/develop first." }
    if (-not $State.target) { return & $fail 'origin/develop could not be resolved after fetch.' }
    $actions = @()
    if ($State.head -ne $State.target) { $actions += 'checkout' }
    if (-not $State.listening) { $actions += 'serve' }
    [pscustomobject]@{ ok = $true; error = $null; actions = $actions }
}

function Get-PlaceSyncTaskName {
    <# One task per repository, derived from the repo folder name. #>
    param([Parameter(Mandatory)][string]$RepoRoot)
    $name = (Split-Path -Leaf ($RepoRoot.TrimEnd('/', '\'))) -replace '[^A-Za-z0-9._-]', '-'
    "place-sync-$name"
}
