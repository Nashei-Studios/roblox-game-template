# ADR 0073: Load and join limits in the perf-budget gate

- Status: accepted
- Date: 2026-11-15
- Extends: ADR 0019 (performance budget), ADR 0032 (join architecture)
- Refs: #201

## Context

`scripts/perf-budget` only checked remote bandwidth. The slow entry of a game made from this template comes from other places: how many instances the place replicates, how long a join waits on a session lock, and how many DataStore requests a join issues. None of those had a number or a test, so a change could make them worse without CI noticing. The research note that backs this (vault `research/2026-11-12-rendimiento-y-carga.md`, section 6, decision D3) compared three ways to watch them in CI.

## Options considered

| Option | Catches a regression | False reds | Cost |
|---|---|---|---|
| A. Extend `perf-budget` with pure rules over the place export, a simulated clock and a counting fake | Yes | Few | One step that already exists |
| B. Measure in Studio inside CI | Yes | High: Studio does not run on hosted runners | Not possible |
| C. Manual checklist only | No | None | Kept as the floor (`docs/game/` load page and QA checklist) |

## Decision

Option A. The step `Performance budget` of the `gate` job runs the same command; no job is added, so CI minutes do not grow.

- `src/shared/perf/LoadBudget` (pure) holds the three rules; `scripts/perf-budget` reads files and reports.
- Limits live in `PerfBudget.load`, the same config table as the rest of ADR 0019, each tagged "sourced" or "chosen".
- Instances: the place export is a JSON file (`PerfBudget.load.placeCountsPath`). A capped service missing from it fails; a missing file skips the check and prints it, because the template ships no place.
- Session wait: `JoinPolicy.newWait` runs against a lock holder that never answers, with a simulated clock. An unbounded wait is reported, not hung on.
- DataStore: a real `PlayerDataService.join` over a repository decorator that counts `load`, `save` and `release`.

## Consequences

- Positive: each rule fails with a specific line and has a test; raising a limit is a visible diff in `PerfBudget.luau`.
- Positive: changing `JoinPolicy.MAX_WAIT_SECONDS` above the cap breaks the gate.
- Negative: the instance rule is only as good as the export a game keeps up to date; nothing in this repo produces it yet.
- Negative: the DataStore count covers the template's join path, not requests a game adds in its own join code.
- Negative: the caps are "chosen" until a game measures its place.

## What would change this decision

Luau Execution in the cloud publishing quotas and times would allow measuring on a real server from CI.
