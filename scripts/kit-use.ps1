#requires -Version 7
<#
.SYNOPSIS
  Copies a kit from this person's kit library into the git-ignored assets/kits/<slug> (ADR 0067).
.DESCRIPTION
  The manifest names a kit by a path relative to the library; where the library lives differs per
  machine. It is resolved in this order:
    1. -Library
    2. the environment variable NASHEI_KITS
    3. biblioteca."10-kits" of ~/Nashei/puesto.json (written by studio/tools/puesto.ps1)
    4. ~/Nashei/biblioteca/10-kits
  A kit whose manifest entry says ships = "no" is reference material: it is refused.
.EXAMPLE
  pwsh scripts/kit-use.ps1 rblx-essentials-studded-ui
  pwsh scripts/kit-use.ps1 -List
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Slug,
    [string]$Library,
    [switch]$List
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent

function Resolve-Library {
    if ($Library) { return $Library }
    if ($env:NASHEI_KITS) { return $env:NASHEI_KITS }
    $config = Join-Path $HOME 'Nashei' 'puesto.json'
    if (Test-Path -LiteralPath $config) {
        $mapped = (Get-Content -LiteralPath $config -Raw | ConvertFrom-Json -AsHashtable).biblioteca?['10-kits']
        if ($mapped) { return $mapped }
    }
    return (Join-Path $HOME 'Nashei' 'biblioteca' '10-kits')
}

# One entry per { ... } block of the manifest: slug, ships and libraryPath are plain string fields.
$manifest = Get-Content -LiteralPath (Join-Path $repo 'assets' 'kits.manifest.luau') -Raw
$kits = foreach ($block in [regex]::Matches($manifest, '\{[^{}]*slug\s*=\s*"[^"]+"[^{}]*\}')) {
    $field = { param($name) ([regex]::Match($block.Value, "$name\s*=\s*""([^""]*)""")).Groups[1].Value }
    [pscustomobject]@{ slug = & $field 'slug'; ships = & $field 'ships'; libraryPath = & $field 'libraryPath' }
}

$root = Resolve-Library
if ($List) {
    "Library: $root"
    $kits | ForEach-Object { '{0,-8} {1,-22} {2}' -f ((Test-Path -LiteralPath (Join-Path $root $_.libraryPath)) ? 'here' : 'missing'), "ships=$($_.ships)", $_.slug }
    return
}
if (-not $Slug) { throw 'Give a kit slug, or -List to see them.' }
$kit = $kits | Where-Object slug -eq $Slug
if (-not $kit) { throw "Kit '$Slug' is not in assets/kits.manifest.luau." }
if ($kit.ships -eq 'no') { throw "Kit '$Slug' does not ship (ships = ""no""): it is reference material and stays out of the game." }
$source = Join-Path $root $kit.libraryPath
if (-not (Test-Path -LiteralPath $source)) {
    throw "Kit '$Slug' is not in the library at $root. Bring the library up to date: pwsh <studio>/tools/puesto.ps1 install"
}
$target = Join-Path $repo 'assets' 'kits' $Slug
if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
Copy-Item -LiteralPath $source -Destination $target -Recurse
"copied $Slug -> assets/kits/$Slug  (Rojo: `"`$path`": `"assets/kits/$Slug`")"
