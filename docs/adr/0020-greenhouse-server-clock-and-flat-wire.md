# ADR 0020: Greenhouse timers run on the server clock; the wire is flat; open points taken simply

- Status: proposed (game-level decision for `2026-11-greenhouse`; Victor has not approved the game)
- Date: 2026-11-03
- Source: design draft `games/2026-11-greenhouse/index.md` in the vault, template ADRs 0009, 0012, 0014, 0015, 0016, 0017, 0019
- Numbering: this branch has no 0020 from key-sprint because the two games live on separate branches cut from `feature/perf-budget`. If both branches reach `main`, one of the two ADRs is renumbered.

## Context

The loop is plant, wait a real-time timer, harvest, sell, upgrade. A client that says "my plant finished" can harvest instantly and the game has no value. The design also asks for timers that keep running while the player is away, for at most 2 passes and 2 developer products, and for no time skips. Studio-owned content is not edited through files, so the world is generated from data.

## Options considered

### A. Who decides that a timer finished

| Option | Cheat resistance | Offline growth | Cost |
|---|---|---|---|
| 1. Client counts down and tells the server "done" | None | No | Lowest |
| 2. Server stores an absolute `readyAt` (server time) and compares it with its clock at harvest | High: the client sends only the plot index | Yes, the value is in the profile | A clock port and one pure module |
| 3. Server runs one `task.delay` per plant and flags the plot ready | High | Lost on a server restart unless rebuilt | A scheduler to keep alive per plot |

### B. Server time source

| Option | Notes |
|---|---|
| `os.time()` | Whole seconds, Unix epoch, same on every server. Enough for timers of 15 s and up |
| `workspace:GetServerTimeNow()` | Float seconds, synchronized with clients. The client uses it to display the countdown |

### C. Wire shape

| Option | Budget check (ADR 0019) | Cost |
|---|---|---|
| 1. One snapshot event with arrays and structs | `RemoteBudget.parseSchema` does not size structs or arrays, so the check would undercount | Extend the calculator |
| 2. Flat events: `PlotChanged(plot, crop, readyAt)`, `StockChanged(crop, seeds, produce)`, `PassChanged`, `CoinsChanged` | Every payload is a fixed size the calculator already measures | More event kinds, a dirty set flushed every 0.5 s |

## Decision

A2, B (server `os.time()` through a `Clock` port, client `GetServerTimeNow()` for display only), C2.

- `GrowthTimers` (pure) computes `remaining` and `isReady` from `readyAt` and an injected `Clock`. The remaining time is clamped to the crop's `growSeconds`, so a clock that moved backwards cannot lock a plot for longer than the crop allows.
- `Greenhouse` (pure) holds the rules over a slice of player data: plant, harvest, sell, buy plot, buy seed, auto-harvest. Numbers live in `GreenhouseData` (chosen, not measured).
- `GreenhouseController` (pure, shared) is the handler: rate limiter first, then `Validation`, then the rule. A rejected action marks the plot dirty so the client resyncs to the server state.
- Player data schema v4 (pure step v3 to v4, ADR 0014): `plots`, `seeds`, `produce`, `totalHarvests`. A plot is `{ cropId: string, readyAt: number }` with `cropId = ""` for empty (no sparse tables, no nil holes in a profile).
- Passes are not saved: ownership is read from Roblox at join and after the purchase prompt, and the controller asks `ownsPass`.

### Open points of the design, taken the simplest way

| Open point | Taken |
|---|---|
| Crops, timers, prices | Three crops (radish 15 s, carrot 60 s, pumpkin 300 s), numbers in `GreenhouseData`, all unmeasured. The 15 s radish is the design's first timer |
| One harvest yields | One unit of produce. No random yield |
| "Better seeds" | Carrot and pumpkin seeds are bought with coins; no unlock gate |
| Plot count | Start with 1, buy up to 6, the ExtraPlots pass raises the cap by 4 (to 10). The price rises with the owned count |
| Seed bundle | A fixed pack of carrot seeds (`seeds` grant kind). Over the per-crop cap it is clamped and still reported as granted, because a failed grant makes Roblox retry the receipt forever (ADR 0016) |
| Auto-harvest | One remote: harvests every ready plot and replants the same crop while seeds remain. Pass-gated on the server |
| `tutorial_complete` | The first accepted sell of a player with `totalHarvests = 0` at join (the design puts it at second 55-60, when the second plot is offered) |
| Pass and product ids | Configuration without value (`nil` with a TODO). No id is invented |
| Day-7 read | Out of scope; the template has no day-7 event |

## Consequences

Positive: no client number or time is trusted; timers survive restarts and absence; every payload is a fixed size the budget calculator measures; rules, timers, migration and the HUD view run under Lune with coverage.

Negative: `os.time()` has one-second resolution, so a harvest can be judged up to one second differently from a float clock (irrelevant for timers of 15 s and up); the client countdown can drift by the sync error of `GetServerTimeNow()` and may show 0 slightly before the server accepts (the server wins and resyncs); the state sync is eventually consistent (0.5 s flush); several small event kinds instead of one snapshot; parcels and HUD are generated and plain until art is added in Studio.

## What would change this decision

A calculator that sizes arrays and structs (then one snapshot event is simpler), sub-second timers (switch the port to `GetServerTimeNow()`), or measured exploits that pass the server check (add per-plant tokens).
