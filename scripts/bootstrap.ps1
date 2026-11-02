#Requires -Version 7
<#
.SYNOPSIS
    One-time, idempotent machine setup for this template (Windows, PowerShell 7).
.DESCRIPTION
    Checks Studio, installs the pinned toolchain via Rokit, installs the Rojo Studio
    plugin, creates the `roblox` VS Code profile with 4 extensions, checks the Studio
    MCP registration, and prints what is still manual. Opens no windows.
    Safe to re-run. Every step prints OK or FAIL; exit code is 1 if any step failed.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:failures = 0
$repoRoot = Split-Path -Parent $PSScriptRoot

function Write-Step {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $status = if ($Ok) { 'OK  ' } else { 'FAIL' }
    if (-not $Ok) { $script:failures++ }
    $suffix = if ($Detail) { " - $Detail" } else { '' }
    Write-Host "[$status] $Name$suffix"
}

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# 1. Roblox Studio installed?
$studio = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Roblox\Versions') -Filter 'RobloxStudioBeta.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
Write-Step 'Roblox Studio installed' ($null -ne $studio) $(if ($studio) { 'found' } else { 'install it from roblox.com, then re-run' })

# 2. Rokit available, then pinned tools.
$hasRokit = Test-Command 'rokit'
Write-Step 'Rokit on PATH' $hasRokit $(if (-not $hasRokit) { 'install from https://github.com/rojo-rbx/rokit (read install.ps1 first), open a new terminal' })
if ($hasRokit) {
    Push-Location $repoRoot
    & rokit install 2>&1 | Out-Null
    $rokitOk = ($LASTEXITCODE -eq 0)
    Pop-Location
    Write-Step 'rokit install (rokit.toml)' $rokitOk $(if (-not $rokitOk) { 'if it asks to trust a tool, run `rokit trust <tool>` or `rokit install` by hand once' })
} else {
    Write-Step 'rokit install (rokit.toml)' $false 'skipped, Rokit missing'
}

# 3. Rojo Studio plugin (also upgrades).
if (Test-Command 'rojo') {
    & rojo plugin install 2>&1 | Out-Null
    Write-Step 'rojo plugin install' ($LASTEXITCODE -eq 0)
} else {
    Write-Step 'rojo plugin install' $false 'rojo not on PATH (new terminal after Rokit install?)'
}

# 4. VS Code profile `roblox` with the 4 extensions (the profile is created on first install).
$extensions = @('JohnnyMorganz.luau-lsp', 'evaera.vscode-rojo', 'Kampfkarren.selene-vscode', 'JohnnyMorganz.stylua')
if (Test-Command 'code') {
    foreach ($extension in $extensions) {
        & code --profile roblox --install-extension $extension --force 2>&1 | Out-Null
        Write-Step "VS Code extension $extension" ($LASTEXITCODE -eq 0)
    }
} else {
    Write-Step 'VS Code CLI (code)' $false 'not on PATH'
}

# 5. Studio MCP registered for Claude Code (project scope comes from .mcp.json).
if (Test-Command 'claude') {
    $mcpList = (& claude mcp list 2>&1 | Out-String)
    Write-Step 'claude mcp list shows Roblox_Studio' ($mcpList -match 'Roblox_Studio') 'a failed health check is normal until Studio is open with MCP enabled'
} else {
    Write-Step 'Claude Code CLI (claude)' $false 'not on PATH'
}

Write-Host ''
Write-Host 'Still manual (cannot be automated safely):'
Write-Host '  1. Log in to Roblox Studio and enable 2FA on the account.'
Write-Host '  2. In Studio: Assistant > Manage MCP Servers > Enable Studio as MCP server.'
Write-Host '  3. Open a DEV/throwaway place first, never a production place.'
Write-Host '  4. Check the MCP answers (Studio open): claude mcp get Roblox_Studio'
Write-Host '  5. Start syncing: `rojo serve`, then Connect in the Rojo plugin.'

if ($script:failures -gt 0) {
    Write-Host ''
    Write-Host "$($script:failures) step(s) failed. Fix them and re-run; the script is idempotent."
    exit 1
}
exit 0
