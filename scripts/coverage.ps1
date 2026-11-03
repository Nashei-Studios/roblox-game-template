#Requires -Version 7
<#
.SYNOPSIS
    Line coverage of the pure Luau code (ADR 0017): runs the suites under the Luau CLI with
    --coverage, then gates the total at 75 % with a per-file report.
.DESCRIPTION
    Writes the lcov to logs/coverage.lcov (logs/ is gitignored). Fails when the total is under
    the threshold or when a non-excluded file never appears in the lcov.
    Needs `luau` and `lune` from rokit.toml (`rokit install`).
#>
param([int]$Threshold = 75)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + $env:Path
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    New-Item -ItemType Directory -Force logs | Out-Null
    # luau writes coverage.out into the working directory; move it under logs/.
    & luau --coverage scripts/test_luau.luau
    if ($LASTEXITCODE -ne 0) { throw "tests failed under the Luau CLI (exit $LASTEXITCODE)" }
    Move-Item -Force coverage.out logs/coverage.lcov
    & lune run scripts/coverage_report logs/coverage.lcov $Threshold src
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
