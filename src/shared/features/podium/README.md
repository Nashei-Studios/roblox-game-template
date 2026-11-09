# features/podium

The top three of a board as avatar statues on a 3-step podium in the world, with a name plate each. Decision: [ADR 0056](../../../../docs/adr/0056-podium3d-world-leaderboard.md). Issue #50. Vault bar W19.

## What it is / is not

- Is: pure Luau (loads under Lune) plus one engine adapter. Reads a source through a port, filters names, formats values, colors the plates with the rarity language, caches by interval.
- Is not: the board itself (that is `features/leaderboards`), a text wall (`RigBoard`-style rows, rows 4 to N), a remote, or art. It never trusts a client.

## Tree

```
podium/
  PodiumConfig.luau   words, unit, medal tiers, refresh, geometry; problems()
  PodiumLayout.luau   step and statue positions as plain numbers
  PodiumModel.luau    entries + names -> three places (plate text, medal colors, empty pedestal)
  PodiumNames.luau    lookup + TextService filter; unknown name on any failure
  PodiumSources.luau  fromStore / fromCache / inMemory over the PodiumSource port
  PodiumFormat.luau   compact values: 999, 1.2K, 12K, 3.4M
  Podium.luau         service: tick(), view(), cache and failure policy
ports/PodiumSource.luau
server/adapters/PodiumStage.luau   steps, plates, statues (Players:CreateHumanoidModelFromUserId)
```

Why split: rules and words change with design, the source with the store, the stage with art.

## Adopt in a game

1. Set `Config.default.podium` (board id, title, unit, tiers). Run `lune run scripts/perf-budget`: it fails when the refresh is under the budget.
2. On the server build the source. With `Leaderboards` running: `PodiumSources.fromCache(function() return board:top(config.boardId) end)` (no new store read). Without: `PodiumSources.fromStore(store, function() return BoardKey.storeKey(...) end)`.
3. Build `PodiumNames.new({ lookup = Players.GetNameFromUserIdAsync wrapper, filter = TextServiceNameFilter.new(...), unknownName, onError })`, then `Podium.new({ config, rarity, surfaceHex, source, nameOf, formatValue, now = os.time, onError })` (`formatValue` is the game's own formatter, nil uses PodiumFormat).
4. Build `PodiumStage.new({ config, origin, parent, maxParts = PerfBudget.podium.maxParts, onError })` with the `origin` CFrame kept in the game's world data.
5. Loop once per second: `if podium:tick() then stage:render(podium:view()) end`. Call it after the board tick.

## Behavior to know

- First tick always renders (three empty pedestals when the source is empty or failing: "Be the first").
- A failed read keeps the last good view and waits a full interval.
- A statue is rebuilt only when its occupant changes. If the avatar fails to load the plate still shows.
- Idle animation: set `idleAnimationId` to an allowed asset; nil keeps a static pose.

## Forbidden

A client script on a statue; a remote for the board; reading the store per join; showing a raw (unfiltered) name; invented animation or asset ids.

## Tests

`tests/features/podium/Podium.test.luau` (config, format, layout, model, names, cache, failure). The stage is engine code and is checked in Studio.

## Placement, scale and tags (found in Studio)

- Statues are placed by their feet: root center = step top + `HipHeight` + half the root height, then the lowest foot is aligned to the step top (`PodiumLayout.rootCenterY`, `feetShift`). Never by bounding box: an accessory that did not weld sat 500 studs away and broke it.
- The model is parented in the world with the root anchored, accessories without a joint are re-welded (`Humanoid:AddAccessory`), physics settles for 0.1 s, and only then everything is anchored. A part farther than `PodiumLayout.strayRadius(statueScale)` from its step is removed and reported.
- `layout.statueScale` scales the avatar (`Model:ScaleTo`); the steps are set in the same config. Keep statues about as tall as the camera of the game, or the head leaves the frame.
- Each place has a plate on the front face (`NormalId.Back` of the plate part, the +Z side) and a screen-sized `BillboardGui` tag at the step edge: pixel size, legible at any distance up to 160 studs, zero parts.
