# Factory timing: Greenhouse (2026-11-greenhouse)

Second game of the 3-games-per-week factory. Times are wall clock, 2026-11-03, taken from `date` at the boundary of each stage. Duration is end minus start; waiting on a tool run is included. A cell reads "not recorded" when no `date` was taken at that boundary; nothing is estimated.

| # | Stage | Start | End | Minutes | Notes |
|---|---|---|---|---|---|
| 1 | Read design | 05:07 | 05:12 | 5 | Worker I, from its `logs/times.txt` (minute resolution) |
| 2 | Flow diagram and ADR 0020 | 05:12 | 05:13 | 1 | Worker I (commit e7e0eb3) |
| 3 | Pure core (growth rules, schema v4, seed grants) | 05:12 | 05:18 | 6 | Worker I (commit 3811440); overlaps stage 2 in its log |
| 4 | Server core (controller, funnel) | not recorded | 05:20 | n/a | Worker I (commit 7d44245); start not logged |
| 5 | Zap remotes, perf budget, plot layout, server wiring, builder | not recorded | not recorded | n/a | Worker I wrote them uncommitted before the 05:23 quota cut; no boundary times were taken |
| - | CUT | 05:23 | 09:17 | n/a | Worker I stopped at about 05:23 (quota). Worker I2 resumed at 09:17:04 |
| 6 | Resume: run the gate on the uncommitted work, fix 2 red checks (stale remote-budget contract test, one type error in a test), commit 0c29bfe | 09:17:04 | not recorded | n/a | Boundary not taken between this stage and stage 7 |
| 7 | Pure HUD model with tests, HUD adapter, client wiring, gate, commit 9b733b4 | not recorded | 09:23:41 | n/a | Stages 6 and 7 together: 09:17:04 to 09:23:41 = 6 min 37 s |

Gate at the end of stage 7: stylua check, selene (0 errors), analyze (0 type errors), 198 tests passing, perf-budget OK (394 of 512 B/s up, 290 of 2048 B/s down), coverage 98.1 %, rojo build OK.
