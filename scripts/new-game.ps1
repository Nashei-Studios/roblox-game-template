#requires -Version 7
<#
.SYNOPSIS
  Stamps a new private game repo from vruizz22/roblox-game-template (decision 0014, step B1).
.DESCRIPTION
  Validates the slug, creates the repo with `gh repo create --template`, clones it under
  D:\Victor\Repositorios\roblox\games\<slug>, renames the game where the template fixes the
  name, optionally writes the game note in the vault, and prints the NAMES of the environment
  variables the next steps need (never their values).
  -DryRun prints the commands and changes nothing.
.EXAMPLE
  pwsh scripts/new-game.ps1 -Slug tap-the-slime -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Slug,
    [switch]$DryRun,
    [string]$VaultPath,
    [string]$GamesRoot = 'D:\Victor\Repositorios\roblox\games',
    [string]$Owner = 'vruizz22',
    [string]$TemplateRepo = 'vruizz22/roblox-game-template'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SlugPattern = '^[a-z0-9]+(-[a-z0-9]+)*$'
$RequiredEnvVars = @(
    @{ Name = 'ASPHALT_API_KEY'; Purpose = 'assets key (asset:read, asset:write), used by asphalt sync' }
    @{ Name = 'ROBLOX_API_KEY'; Purpose = 'Open Cloud publish key (universe-places:write, universe:write, universe.place:write)' }
)

function Test-Slug([string]$Value) {
    return ($Value.Length -le 50) -and ($Value -cmatch $SlugPattern)
}

function ConvertTo-Title([string]$Value) {
    $words = $Value -split '-' | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }
    return ($words -join ' ')
}

if (-not (Test-Slug $Slug)) {
    Write-Error "Invalid slug '$Slug': use kebab-case ASCII (a-z, 0-9, single hyphens), at most 50 characters."
    exit 2
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error 'gh (GitHub CLI) was not found on PATH.'
    exit 3
}

$repo = "$Owner/$Slug"
$target = Join-Path $GamesRoot $Slug
$title = ConvertTo-Title $Slug
$createArgs = @('repo', 'create', $repo, '--private', '--template', $TemplateRepo)
$cloneArgs = @('repo', 'clone', $repo, $target)

if ($DryRun) {
    Write-Output '[dry-run] nothing will be created or changed'
    Write-Output "[dry-run] gh $($createArgs -join ' ')"
    Write-Output "[dry-run] gh $($cloneArgs -join ' ')"
    Write-Output "[dry-run] set name '$Slug' in default.project.json and gameName '$title' in src/shared/Config.luau"
    if ($VaultPath) { Write-Output "[dry-run] write game note under $VaultPath" }
}
else {
    & gh repo view $TemplateRepo --json isTemplate -q .isTemplate | Out-String | ForEach-Object {
        if ($_.Trim() -ne 'true') { throw "$TemplateRepo is not marked as a template repository (Victor action, decision 0014)." }
    }
    if (Test-Path -LiteralPath $target) { throw "Target folder already exists: $target" }
    & gh @createArgs
    if ($LASTEXITCODE -ne 0) { throw 'gh repo create failed.' }
    & gh @cloneArgs
    if ($LASTEXITCODE -ne 0) { throw 'gh repo clone failed.' }

    $projectFile = Join-Path $target 'default.project.json'
    $project = Get-Content -LiteralPath $projectFile -Raw
    $project = $project -replace '"name":\s*"roblox-game-template"', "`"name`": `"$Slug`""
    Set-Content -LiteralPath $projectFile -Value $project -NoNewline

    $configFile = Join-Path $target 'src/shared/Config.luau'
    $config = Get-Content -LiteralPath $configFile -Raw
    $config = $config -replace 'gameName = "My Game",[^\r\n]*', "gameName = `"$title`","
    Set-Content -LiteralPath $configFile -Value $config -NoNewline

    $readmeFile = Join-Path $target 'README.md'
    $readme = Get-Content -LiteralPath $readmeFile -Raw
    $readme = $readme -replace '^# roblox-game-template', "# $Slug"
    Set-Content -LiteralPath $readmeFile -Value $readme -NoNewline

    Write-Output "Stamped $repo at $target (not committed: review the diff, then commit and push)."

    if ($VaultPath) {
        $month = Get-Date -Format 'yyyy-MM'
        $noteDir = Join-Path $VaultPath "games/$month-$Slug"
        New-Item -ItemType Directory -Force -Path $noteDir | Out-Null
        $note = @"
---
type: game
title: "$title"
status: idea
genre: replace-with-genre
repo: "https://github.com/$repo"
---
# $title

Core loop: _fill in_

## Status log

- $(Get-Date -Format 'yyyy-MM-dd'): stamped from the template
"@
        Set-Content -LiteralPath (Join-Path $noteDir 'index.md') -Value $note
        Write-Output "Game note written: $noteDir/index.md"
    }
}

Write-Output 'Environment variables needed later (names only, set them yourself):'
foreach ($v in $RequiredEnvVars) {
    Write-Output "  $($v.Name) - $($v.Purpose)"
}
