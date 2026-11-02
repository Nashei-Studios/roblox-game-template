# ADR 0008: CI gates on the stable type solver; the new solver runs non-blocking

- Status: accepted by recommendation 2026-11-02, revisable
- Date: 2026-11-02
- Source: R1 dev-system research (D-23)

## Context

The new Luau type solver is still preview in luau-lsp (`enableNewSolver` defaults to `false`) and is not the Studio default. Its error text and edge cases move between releases.

## Options considered

1. Gate on the stable (old) solver only.
2. Gate on the new solver.
3. Gate on the stable solver, plus a second non-blocking job on the new solver.

## Decision

Option 3. `luau-lsp analyze` accepts `--flag:KEY=VALUE`; `--flag:LuauSolverV2=true` enables the new solver (verified 2026-11-02 on luau-lsp 1.70.1: the pre-fix `harness.luau:48` error appears with the default solver and disappears with the flag, so the flag takes effect). The `analyze` job is blocking. The `analyze-new-solver` job has `continue-on-error: true` and shows drift early. `scripts/analyze.ps1 -NewSolver` reproduces it locally.

## Consequences

- Positive: no surprise breakage from a preview solver; early signal for the migration.
- Negative: one more CI job (about one extra minute per run); code may pass one solver and warn on the other.

## What would change this decision

Roblox making the new solver the Studio default, or luau-lsp flipping `enableNewSolver` to `true`: then gate on it and make the old one the informational job.
