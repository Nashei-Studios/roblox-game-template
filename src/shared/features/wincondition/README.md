# features/wincondition

The win-condition declaration of a game and its check. Decision: [ADR 0043](../../../../docs/adr/0043-win-condition-checklist-and-gate.md). Issue #91. The human checklist is [docs/win-condition-checklist.md](../../../../docs/win-condition-checklist.md).

## What it is / is not

- Is: a typed declaration (`WinConditionConfig`) and a pure `validate` that returns `missing` (empty fields) and `problems` (filled but wrong). `scripts/win-condition.luau` runs it over `Config.default.winCondition`.
- Is not: a measurement. Numbers of the stage 12 table are read by a person from Creator Analytics and written with an `as_of` date; nothing here fills them.

## Tree

```
wincondition/WinCondition.luau   types, empty(), validate(declaration, knownMomentIds?)
scripts/win-condition.luau       Lune gate: default = pending allowed, --strict = nothing missing
docs/win-condition-checklist.md  the checklist with its test per criterion
```

## Adopt in a game

1. Stage 1: fill `Config.default.winCondition` (hypothesis, hook of at most 9 words, borrowed channel, funny element, measurement plan, owner and date) and declare the moment ids once the clip moments exist.
2. Run `lune run scripts/win-condition --strict`; stage 1 does not close until it exits 0.
3. Pass `knownMomentIds` (the ids of your clip-moment config) from a game test so a shareable id cannot point at nothing.
4. Stages 7 and 8: walk the criteria table with a captured playtest; a criterion that cannot be tested stays `pending`.
5. Stage 12: fill the measurement table with values and dates, never precompleted.

## Forbidden here

A game name, a threshold presented as Roblox official, a plausible value in the measurement table, making the template CI strict.

## Tests

`tests/features/wincondition/WinCondition.test.luau`, registered in `scripts/suites.luau`; the stamping output in `scripts/new-game.test.ps1`.
