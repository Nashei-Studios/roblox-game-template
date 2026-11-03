# Dot-sourced by new-game.ps1 and new-game.test.ps1: vault game note handling.

function Get-GameNotePath([string]$VaultPath, [string]$Month, [string]$Slug) {
    return Join-Path $VaultPath "games/$Month-$Slug/index.md"
}

function Write-GameNote([string]$NotePath, [string]$Content) {
    # An existing note is the owner's design work: never overwrite it.
    if (Test-Path -LiteralPath $NotePath) {
        Write-Output "Game note already exists: $NotePath (left unchanged)"
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $NotePath) | Out-Null
    Set-Content -LiteralPath $NotePath -Value $Content
    Write-Output "Game note written: $NotePath"
}
