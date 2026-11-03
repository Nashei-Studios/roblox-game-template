# 2026-11-03: Performance budget (ADR 0019)

## Goal
Give the template a performance budget that can fail CI: remote bandwidth from the Zap schema times the RateLimiter, plus a Studio probe and a manual procedure.

## What was done
- Research with context7 and create.roblox.com pages (sources listed in `docs/performance.md`). Found: 16 ms server CPU / 16.67 ms frame, Heartbeat cap 60, server memory below 50 % of 6.25 GiB + 100 MiB per player, RemoteEvent throttle about 500/s per client, UnreliableRemoteEvent 1,000 byte drop, `--!native` and Parallel Luau guidance (qualitative).
- **Not found in the docs**: any recommended per-player network figure for `Stats.DataSendKbps` / `DataReceiveKbps`, a script-time budget, a native-code size limit value. Those budgets are labelled "chosen, not sourced" in `PerfBudget.luau` and the docs.
- `src/shared/perf/` (PerfBudget, RemoteBudget, ProbeEvaluator), `scripts/perf-budget.luau`, `src/server/dev/PerfProbe.luau`, tests in `tests/perf/` (13 new tests), CI step, ADR 0019, `docs/performance.md`, README, architecture, CLAUDE.md.
- `Main.server` now builds the RequestPurchase limiter from `PerfBudget.clientRemotes` (same numbers, 3 and 0.5) so CI checks what runs. `Config.perfProbeEnabled` (optional, default false).

## Decisions
- Option B (static calculator + probe) over a checklist only or an external service; see the ADR.
- Worst case per second for a client remote is `capacity + refillPerSecond` events; a remote with no declared rate, an unbounded type or a stale budget entry fails.
- Zap wire sizes (u16 string length prefix, 1-byte enum up to 256 variants) are modelled from Zap's format and were not verified against its source.

## Verification
`stylua --check .`, `selene .` (0 errors, 0 warnings), `pwsh scripts/analyze.ps1` (exit 0), `lune run scripts/test` (130 passed, 0 failed), `pwsh scripts/coverage.ps1` (97.7 %), `rojo build` ok, `lune run scripts/perf-budget` OK (31.5 B/s up, 24 B/s down). Logs in `logs/*-perf.log` (gitignored).

## Open items
- The probe and the Studio procedure were not run in Studio (not opened by instruction). `Stats.HeartbeatTime` is read as seconds per the docs.
- The chosen network budgets need a real measurement before a launch.
- CI not run (no remote).
