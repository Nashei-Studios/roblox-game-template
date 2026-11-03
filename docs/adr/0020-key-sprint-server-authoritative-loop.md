# ADR 0020: Key sprint loop is server-authoritative; stages are generated from data

- Status: proposed (game-level decision for `2026-11-key-sprint`; Victor has not approved the game)
- Date: 2026-11-03
- Source: design draft `games/2026-11-key-sprint/index.md` in the vault, template ADRs 0009, 0012, 0014, 0015, 0016, 0017, 0019

## Context

The game loads a speed multiplier by key presses and uses it to run an obstacle stage. A client that reports its own speed or multiplier can cheat it to the cap instantly, and the gimmick has no value if it can be skipped. The design also asks for stages that do not depend on hand-building the world in Studio (Studio-owned content is not edited through files, and an agent cannot playtest without the lock).

## Options considered

### A. Where the multiplier lives

| Option | Cheat resistance | Latency feel | Cost |
|---|---|---|---|
| 1. Client computes the multiplier and walk speed, server trusts it | None | Best | Lowest |
| 2. Client sends press batches, server computes multiplier and sets WalkSpeed | High: the server clips to the player cap and to a press rate | Meter lags by a batch (about 0.25 s) | One remote, one pure module |
| 3. Server samples raw key events one by one | High | Same | Rate of remote calls per press breaks the bandwidth budget (ADR 0019) |

### B. Where stages come from

| Option | Playtest without Studio | Finish validation | Cost |
|---|---|---|---|
| 1. Hand-built in Studio | No | Needs hand-measured times | Studio time per stage, a place file nobody can merge |
| 2. Generated at runtime from `StageSpec` data | Layout is unit-tested under Lune | Path length is known, so a minimum plausible time is computed | A small builder adapter; looks plain until art is added in Studio |

## Decision

A2 and B2.

- `ChargeMeter` (pure, shared) accepts press batches validated with `Validation` and limited by a `RateLimiter` (cost = presses), applies a decay with an injected clock, and clips to the player's `multiplierCap`. The walk speed is `16 x multiplier`, set by the server.
- The Faster charge pass raises charge per press by a fixed factor. It never raises the cap, so it stays inside the server cap.
- `StageSpecs` holds three stages; `StageLayout` turns a spec into boxes; `StageBuilder` (engine adapter) instantiates them. `StageRuns` rejects a `Finish` that is not for the active stage or that arrives sooner than `pathLength / (16 x cap) x 0.9` seconds after the run began.
- The checkpoint of a stage is its start gate. A death respawns there; it does not reset the run clock, which only makes the minimum time easier to meet, never harder to enforce.
- Player data schema v4 adds `highestStage` and `multiplierCap` (pure step v3 to v4, ADR 0014).
- Skip stage is a new `ProductGrant` kind; at the last stage it is a granted no-op, because a failed grant would make Roblox retry the receipt forever (ADR 0016).

## Consequences

Positive: no client number is trusted; every remote has a bounded size and rate in `PerfBudget`; layout, validation and progression run under Lune with coverage.

Negative: the meter lags by a batch; a plausible-time check is a lower bound, so a player who is fast enough at the real cap is accepted (that is the game); generated stages have no art and gap/jump limits are unmeasured in the engine; the minimum time uses the cap, not the live multiplier, so it is loose on purpose.

## What would change this decision

Measured cheating that passes the time bound (add per-checkpoint touch events), a playtest showing batch lag hurts the feel (shorter batch or client-side prediction of the meter), or a world artist who wants hand-built stages (keep `StageSpec` for collision and times, build the art in Studio).
