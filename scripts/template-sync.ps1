<#
.SYNOPSIS
  Compares a game repo with the template checkout and, with -Apply, copies the files the manifest owns.
.DESCRIPTION
  ADR 0069. The manifest (.templatesync, from the template) lists what the template owns; the game can
  exclude paths in .templatesync.local. Game files the template no longer has are reported (notInTemplate), never removed.
  Files under .github/workflows/ need a token with the `workflow` scope to be pushed; they are
  reported in a separate list so the caller can skip them when it only has GITHUB_TOKEN.
  Runs on pwsh 7 (Windows, Linux, macOS).
.PARAMETER TemplateDir  Checkout of the template at the ref to sync from.
.PARAMETER TargetDir    Game repo root. Defaults to the current directory.
.PARAMETER Apply        Copy changed files. Without it the script only reports.
.PARAMETER SkipWorkflows  Do not copy files under .github/workflows/.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TemplateDir,
    [string]$TargetDir = '.',
    [switch]$Apply,
    [switch]$SkipWorkflows
)
$ErrorActionPreference = 'Stop'

function ConvertTo-Matcher([string]$Glob) {
    $re = [regex]::Escape($Glob.Trim('/'))
    $re = $re.Replace('\*\*', '<<ANY>>').Replace('\*', '[^/]*').Replace('<<ANY>>', '.*')
    return [regex]"^$re(/.*)?$"
}

function Read-Rules([string]$Path, [bool]$ExcludeOnly) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $rules = foreach ($line in Get-Content -LiteralPath $Path) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $exclude = $t.StartsWith('!')
        if ($ExcludeOnly -and -not $exclude) { continue }
        [pscustomobject]@{ Exclude = $exclude; Matcher = ConvertTo-Matcher ($t.TrimStart('!')) }
    }
    return @($rules)
}

function Test-Owned([string]$RelPath, $Rules) {
    $owned = $false
    foreach ($r in $Rules) { if ($r.Matcher.IsMatch($RelPath)) { $owned = -not $r.Exclude } }
    return $owned
}

$template = (Resolve-Path -LiteralPath $TemplateDir).Path
$target = (Resolve-Path -LiteralPath $TargetDir).Path
$manifest = Join-Path $template '.templatesync'
if (-not (Test-Path -LiteralPath $manifest)) { throw "No .templatesync in $template" }

$rules = @(Read-Rules $manifest $false) + @(Read-Rules (Join-Path $target '.templatesync.local') $true)

$files = git -C $template ls-files | Where-Object { Test-Owned $_ $rules }
$changed = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()
foreach ($rel in $files) {
    $src = Join-Path $template $rel
    $dst = Join-Path $target $rel
    $same = (Test-Path -LiteralPath $dst) -and ((Get-FileHash -LiteralPath $src).Hash -eq (Get-FileHash -LiteralPath $dst).Hash)
    if ($same) { continue }
    if ($SkipWorkflows -and $rel.StartsWith('.github/workflows/')) { $skipped.Add($rel); continue }
    $changed.Add($rel)
    if ($Apply) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
}

# Owned paths present in the game but absent from the template (deleted there, or game-only): report only.
$orphans = git -C $target ls-files | Where-Object { (Test-Owned $_ $rules) -and -not (Test-Path -LiteralPath (Join-Path $template $_)) }

[pscustomobject]@{
    changed = @($changed)
    skippedWorkflows = @($skipped)
    notInTemplate = @($orphans)
} | ConvertTo-Json -Depth 3
