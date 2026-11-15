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

function Resolve-StablePwshPath {
    <#
    Picks the pwsh path to register in the scheduler. The Store build lives in a versioned folder
    (WindowsApps/Microsoft.PowerShell_<version>_...) that disappears on update, while the execution
    alias under %LOCALAPPDATA%/Microsoft/WindowsApps/pwsh.exe survives it. Returns the alias when it
    exists, else the running executable. Pure: the existence check is injected.
    #>
    param(
        [Parameter(Mandatory)][string]$Current,
        [string]$LocalAppData,
        [scriptblock]$Exists = { param($p) Test-Path -LiteralPath $p -PathType Leaf }
    )
    if ($LocalAppData) {
        $alias = (Join-Path $LocalAppData 'Microsoft/WindowsApps/pwsh.exe').Replace([char]92, '/')
        if (& $Exists $alias) { return $alias }
    }
    $Current
}

function Get-TaskExecutablePath {
    <# Extracts the pwsh path from a task's conhost argument line (`--headless "<pwsh>" ...`); $null if absent. #>
    param([string]$Argument)
    if ($Argument -match '--headless\s+"([^"]+)"') { return $Matches[1] }
    $null
}

function Get-TaskHealth {
    <# Status warning for a registered task: $null when fine or not registered, else a message. #>
    param(
        [string]$Argument,
        [scriptblock]$Exists = { param($p) Test-Path -LiteralPath $p -PathType Leaf }
    )
    if (-not $Argument) { return $null }
    $exe = Get-TaskExecutablePath $Argument
    if (-not $exe) { return 'The registered task has an unrecognised command line; run install again.' }
    if (-not (& $Exists $exe)) { return "The registered task points to a pwsh that no longer exists ($exe); run install again." }
    $null
}
