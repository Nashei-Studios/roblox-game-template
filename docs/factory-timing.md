# Factory timing: Key sprint (2026-11-key-sprint)

First game of the 3-games-per-week factory. Times are wall clock, 2026-11-03, UTC-3, taken from `date` at the boundary of each stage by the worker. Duration is end minus start; waiting on a tool run is included.

| # | Stage | Start | End | Minutes | Notes |
|---|---|---|---|---|---|
| 0 | Setup: worktree, read design, CLAUDE.md, ADRs, template sources, baseline tests (130 pass) | 04:35:12 | 04:37:14 | 2 | Includes 130 baseline tests passing |
| 1-3 | Pure core, Zap remotes, perf budget, server wiring (commits c0fb7cb, 40db31e) | n/a | n/a | n/a | Done by the first worker; its per-stage times were not recorded before the cut, so they are not filled in |
| - | CUT | 04:52 | 05:01 | n/a | The first worker stopped at 04:52 (5 h cap of another account). Worker E2 resumed at 05:01 |
| 4 | Resume: finish HudModel showSkip, KeySprintHud adapter, client wiring (input, press batches, finish touch), gate | 05:01:00 | 05:02:53 | 2 | Gate run included: stylua, selene, analyze, 224 tests, perf-budget, coverage 98.4 %, remotes, rojo build |
