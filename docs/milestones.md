# Milestones

| Milestone | Scope | Done when |
|---|---|---|
| M1 Skeleton | Repo, toolchain pins, configs, ADRs, docs | Committed on `feature/initial-template` |
| M2 Verified locally | Bootstrap run, Lune tests run, StyLua/Selene clean | All OK on Victor's PC (pending: nothing was executable when M1 was built) |
| M3 Remote and CI | GitHub repo `vruizz22/roblox-game-template` (private), PR merge, CI green | CI green on the first PR |
| M4 Studio loop | Rojo connected, Studio MCP verified on a dev place | `list_roblox_studios` answers from Claude Code |
| M5 First game | Prototype from the template | See roadmap R2 |
| Spike Zap vs Blink | One-day spike (D-27): implement 5 representative remotes (intent-only, typed payloads) in both code generators, compare generated-code type safety under `luau-lsp analyze` (stable and new solver), runtime cost, and maintenance activity; record the winner in an ADR | An ADR chooses one, or rejects both. Not started; do it before the first remote exists |

Cycle: one PR per milestone step, squash merge, tags `vX.Y.Z` after M3.
