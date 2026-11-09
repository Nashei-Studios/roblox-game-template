# features/autofeel

Feel profiles and a pure scheduler for automatic mining. [ADR 0058](../../../../docs/adr/0058-auto-feel-profiles-and-scheduler.md). Refs #159.

## What it is / is not

- Is: `AutoFeel` (config, the `manual`, `auto` and `observer` profiles, `validate`) and `AutoFeelScheduler` (cadence, aggregation, manual override, pause rules). Both load under Lune.
- Is not: a presenter, a prediction of the drill or a place that pays anything. The server pays; the scheduler only decides what to show. The engine side (swing, rock dip, popup, sound) lives in the game.

## Design

The auto profile speaks the same grammar as a manual hit in a quieter voice; the observer profile is the LOD rule for other players (swing only). The scheduler gets server deltas (`noteDelta`), manual swings (`noteManual`) and a per-frame context, and returns whether to swing and whether to show one aggregated popup. Paused or overridden time drops the pending delta.

## Use from a game

```lua
local problems = AutoFeel.validate(config) -- at boot; fail if not empty
local scheduler = AutoFeelScheduler.new(config)
-- on a snapshot: scheduler:noteDelta(powerPaidByTheServerSinceTheLastSnapshot)
-- on a manual swing: scheduler:noteManual(os.clock())
-- every frame:
local tick = scheduler:step(os.clock(), { rate = rate, moving = moving, menuOpen = menuOpen, distance = distance })
if tick.swing then --[[ play the swing with AutoFeel.profile(config, "auto") ]] end
if tick.popup ~= nil then --[[ one "+N" popup ]] end
```

## Forbidden here

No engine services, no number outside the config, no value that did not come from a server snapshot, no new remote.

## Tests

`tests/features/autofeel/AutoFeel.test.luau`. Budget: `PerfBudget.autoFeel`, checked by `lune run scripts/perf-budget`.
