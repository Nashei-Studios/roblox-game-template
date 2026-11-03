# ADR 0017: Line-coverage gate with the Luau CLI

- Status: accepted by recommendation 2026-11-03, revisable
- Date: 2026-11-03
- Source: spike D-31 (`spikes/luau-coverage`, measured 2026-11-02)

## Context

The delivery bar asks for at least 75 % coverage and the template did not measure it. Lune has no coverage (Lune issue 259 is open) and Lute's coverage API (issue 178) is open too. The spike showed that the official `luau` CLI (0.745) runs the unchanged suites with `--coverage` and writes lcov: 96.5 % of the lines in `src/shared` and 98.3 % in the adapters on the copy it measured. Findings that shaped the design: the CLI resolves our relative requires; a module that no test loads (`Result.luau`) is invisible in the lcov; only `scripts/test.luau` used a Lune API.

## Options considered

| Option | Cost | Evidence |
|---|---|---|
| A. `luau --coverage` plus a Lune report script | one pinned CLI, about 150 lines of Luau, a neutral runner with two entries | works today, lcov output, line level only |
| B. Wait for Lune or Lute coverage | none | both issues open, no date |
| C. Coverage inside Roblox (Jest-Lua in engine, Execution API) | high, needs engine runs and a key | no coverage found in jest-lua |
| D. No measurement, rely on review | none | breaks the delivery bar |

## Decision

Option A.

- `rokit.toml` pins `luau = "luau-lang/luau@0.745.0"` (installed after an explicit `rokit trust luau-lang/luau`, never `--no-trust-check`).
- `scripts/suites.luau` is the runtime-neutral runner (the suite list and the loop, no Lune API). `scripts/test.luau` is the Lune entry (`lune run scripts/test`, exits 1 on failure) and `scripts/test_luau.luau` the Luau entry (raises an error on failure).
- `scripts/coverage.ps1` runs `luau --coverage scripts/test_luau.luau`, moves the lcov to `logs/coverage.lcov` (gitignored) and runs `scripts/coverage_report.luau`, which prints per-file and total line coverage. The gate is 75 % of the TOTAL. It also fails when a file that is not excluded is missing from the lcov, so a new module cannot hide at 0 %.
- Excluded: `vendor/`, `types/`, `tests/`, `generated/`, `src/shared/ports/` (type-only), `Main.*`, and any file that touches the engine (`game:X` or `game.X`, detected by the report). The report lists every excluded file.
- CI gets a `coverage` job (10 min timeout, same Rokit action pinned by SHA) that runs the same two commands without PowerShell.
- `Result.luau` had no direct test and was only visible when forced to load; it now has `tests/Result.test.luau`, so no loader shim is needed.
- Measured on this template (101 tests): 97.2 % of 543 lines, lowest file 95.2 %.

## Consequences

- Positive: a measured number against the delivery bar, a per-file view, one new pinned dependency.
- Negative: line coverage only (no branches); engine code is invisible to the gate (it is covered by fakes through adapters, not by itself); two runtimes (Lune and Luau) must keep running the suites; a percentage gate can be met with shallow tests, so review and mutation checks still matter.
- Not verified: the `coverage` CI job has never run on GitHub (the repository has no remote yet); the Linux install of `luau` through Rokit is untested; `@self` requires and `.luaurc` aliases under the Luau runtime are unused by the template and untested.

## What would change this decision

Lune or Lute shipping first-party coverage with branches; the suites needing a Lune-only API; `luau` release churn making the pin costly; an engine-test layer (ADR 0005) producing its own coverage.
