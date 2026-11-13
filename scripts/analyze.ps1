#Requires -Version 7
<#
.SYNOPSIS
    Runs `luau-lsp analyze` the same way CI does (ADR 0007, 0008).
.DESCRIPTION
    Generates the Lune type definitions (`lune setup`) and the Rojo sourcemap, then analyzes
    src, tests and scripts against the vendored Roblox definitions in types/.
    Default: stable (old) solver, the gate. -NewSolver runs the new solver (informational).
    Exit code is luau-lsp's: 0 means no errors.
#>
param([switch]$NewSolver)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + $env:Path
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & lune setup | Out-Null
    & rojo sourcemap default.project.json -o sourcemap.json | Out-Null
    $arguments = @(
        'analyze',
        '--sourcemap', 'sourcemap.json',
        '--definitions=@roblox=types/globalTypes.None.d.luau',
        '--base-luaurc', '.luaurc'
    )
    if ($NewSolver) { $arguments += '--flag:LuauSolverV2=true' }
    # A game may exclude paths (legacy code, generated files) in gate.config.json, the same file
    # coverage_report.luau and CI read. Without the file the gate runs exactly as the template's.
    if (Test-Path -LiteralPath 'gate.config.json') {
        $gate = Get-Content -Raw -LiteralPath 'gate.config.json' | ConvertFrom-Json
        foreach ($glob in @($gate.analyzeIgnore)) { if ($glob) { $arguments += @('--ignore', $glob) } }
    }
    $arguments += @('src', 'tests', 'scripts', '.claude/hooks')
    & luau-lsp @arguments
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
