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

# Vault note handling (temp folders only; never the real vault).
. (Join-Path $PSScriptRoot 'game-note.ps1')
$tmp = Join-Path ([IO.Path]::GetTempPath()) "new-game-test-$([guid]::NewGuid())"
try {
    $month = Get-Date -Format 'yyyy-MM'
    $existing = Get-GameNotePath $tmp $month 'key-sprint'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $existing) | Out-Null
    Set-Content -LiteralPath $existing -Value 'hand-written design note'
    $before = Get-Content -LiteralPath $existing -Raw
    $out = Write-GameNote $existing 'STUB' | Out-String
    Assert-True ((Get-Content -LiteralPath $existing -Raw) -ceq $before) 'existing note is left byte-identical'
    Assert-True ($out -match 'Game note already exists: .*\(left unchanged\)') 'existing note is reported as left unchanged'

    $fresh = Get-GameNotePath $tmp $month 'reef'
    $out = Write-GameNote $fresh 'STUB' | Out-String
    Assert-True ((Test-Path -LiteralPath $fresh) -and ((Get-Content -LiteralPath $fresh -Raw).Trim() -ceq 'STUB')) 'new note is written with its folder'
    Assert-True ($out -match 'Game note written') 'new note is reported as written'

    $r = Invoke-Stamp @('-Slug', 'key-sprint', '-DryRun', '-VaultPath', $tmp)
    Assert-True ($r.Code -eq 0 -and $r.Text -match 'game note already exists, would leave unchanged') 'dry run warns it would leave an existing note'
    Assert-True ((Get-Content -LiteralPath $existing -Raw) -ceq $before) 'dry run leaves the existing note intact'
    $r = Invoke-Stamp @('-Slug', 'greenhouse', '-DryRun', '-VaultPath', $tmp)
    Assert-True ($r.Text -match 'would write game note' -and -not (Test-Path -LiteralPath (Get-GameNotePath $tmp $month 'greenhouse'))) 'dry run says it would write a missing note without writing'
}
finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }

if ($failures -gt 0) { Write-Output "$failures failed"; exit 1 }
Write-Output 'all passed'
