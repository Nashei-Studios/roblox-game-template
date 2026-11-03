#requires -Version 7
# Minimal self-contained suite for scripts/new-game.ps1 (the repo does not use Pester).
# Run: pwsh scripts/new-game.test.ps1  (exit 0 = all passed)
Set-StrictMode -Version Latest
$script = Join-Path $PSScriptRoot 'new-game.ps1'
$failures = 0

function Invoke-Stamp([string[]]$Arguments) {
    $out = & pwsh -NoProfile -NonInteractive -File $script @Arguments 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Text = $out }
}

function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Output "PASS $Name" }
    else { Write-Output "FAIL $Name"; $script:failures++ }
}

foreach ($bad in @('Bad-Slug', 'has space', 'trailing-', '-leading', 'double--hyphen', 'ñandú', 'UPPER', '')) {
    $r = Invoke-Stamp @('-Slug', $bad, '-DryRun')
    Assert-True ($r.Code -ne 0) "rejects slug '$bad'"
}

$r = Invoke-Stamp @('-Slug', 'tap-the-slime', '-DryRun')
Assert-True ($r.Code -eq 0) 'accepts a valid slug in dry run'
Assert-True ($r.Text -match 'gh repo create vruizz22/tap-the-slime --private --template vruizz22/roblox-game-template') 'dry run prints the create command'
Assert-True ($r.Text -match 'ASPHALT_API_KEY' -and $r.Text -match 'ROBLOX_API_KEY') 'prints env var names'
Assert-True ($r.Text -match 'Tap The Slime') 'derives the title from the slug'

$env:ROBLOX_API_KEY = 'dummy-sentinel-value'
$r = Invoke-Stamp @('-Slug', 'tap-the-slime', '-DryRun')
Assert-True ($r.Text -notmatch 'dummy-sentinel-value') 'never prints env var values'
Remove-Item Env:ROBLOX_API_KEY

if ($failures -gt 0) { Write-Output "$failures failed"; exit 1 }
Write-Output 'all passed'
