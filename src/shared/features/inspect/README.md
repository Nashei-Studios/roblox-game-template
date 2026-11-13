# features/inspect

The InspectView mold: a modal that shows one catalog item in 3D and lets the player rotate and zoom it. Decision: [ADR 0060](../../../../docs/adr/0060-inspect-view-mold.md). Issue #125.

## What it is / is not

- Is: a pure state module (`InspectView`: open, close, drag, stick, wheel, pinch, triggers, tap outside, clamps, budget checks, control registration), and a `ModelSource` port. The viewer (ScreenGui, ViewportFrame, WorldModel) is the game UI's.
- Is not: a model builder, an inventory or the card that holds the Inspect button. The game supplies the model and the button.

## Run locally

`lune run scripts/test` (suite `InspectView`), `pwsh scripts/coverage.ps1`, `lune run scripts/perf-budget`. Visual check: Studio Device Emulator at 568x320, 844x390 and 1327x472, each input scheme.

## Tree

```
inspect/InspectView.luau                      state, input mapping, clamps, budget, registry (pure)
ports/ModelSource.luau                        build(itemId) and partCount(itemId) port
tests/features/inspect/                       Lune tests
```

## Adopt in a game

1. Tune `Config.inspect` (speeds, limits, `closeKeys`, `openKeys`). Validated at boot.
2. Call `InspectView.register(registry, config)` once, at bootstrap.
3. Implement `ModelSource` over the builder that makes the item in hand; keep a cached template and clone it in `build`.
4. Open your own viewer from the card Inspect button (named `InspectOpen`) or the pad open key, driven by the `InspectView` state.
5. Check `PerfBudget.inspect.maxParts` against your largest model with `InspectView.budgetProblems`.

## Forbidden here

External meshes, a viewport that stays alive when closed, more than one WorldModel, numbers outside the token scale.
