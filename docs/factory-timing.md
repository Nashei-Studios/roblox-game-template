# Factory timing: Reef (2026-11-reef)

Third game of the 3-games-per-week factory. Times are wall clock, 2026-11-03, taken from `date` at the boundary of each stage by the worker. Duration is end minus start; waiting on a tool run is included.

| # | Stage | Start | End | Minutes | Notes |
|---|---|---|---|---|---|
| 0 | Setup: worktree, read design, CLAUDE.md, template sources, baseline gate | 09:15 | 09:17:26 | 2 | Baseline: 130 tests, coverage 97.7 %; start time estimated, not taken with `date` |
| 1 | docs: reef-flow.md, ADR 0021 | 09:17:26 | 09:20 | 3 | |
| 2 | Pure core with TDD: ReefRules, ReefConfig, FishRoll, ReefController, Funnel, HudModel, schema v4 migration, bait grant | 09:20 | 09:24 | 4 | Gate: stylua, selene, analyze, 174 tests, coverage 98.4 % |
| 3 | Zap remotes, perf budget, FishWire, SellStand adapter, server wiring (rate limits, validation, passes, funnel) | 09:24 | 09:26 | 2 | Gate: stylua, selene, analyze, 175 tests, perf-budget OK (138.5 of 512 B/s up, 81 of 2048 B/s down) |
