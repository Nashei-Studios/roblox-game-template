# features/hitfx

Data-driven hit effect: `HitFx` (pure) and the client presenter `client/presenters/HitFxEmitter`. [ADR 0034](../../../../docs/adr/0034-visible-progression-modules.md). Origin: plus-one-mining F8 (PickaxeHitFx). Refs #47, #76.

## What it is / is not

- Is: a table of hit kinds (`count`, `speedMin`, `speedMax`, `size`, `lifetime`, `glow`) the game defines, validated under Lune, and one reused emitter that bursts any kind in any color.
- Is not: a particle library, a trail system, or a place for game kinds. The kinds belong to the game config.

## Design

One anchored, invisible part and one `ParticleEmitter` for every hit, so a tap burst never allocates. `HitFx.settings` turns a kind into numbers (the shortest particle lives 70 % of the longest). `count` is capped at 40 so a phone stays smooth.

## Use from a game

```lua
local problems = HitFx.validate(kinds) -- at boot; fail if not empty
local fx = HitFxEmitter.new(kinds, "rbxasset://textures/particles/sparkles_main.dds")
fx:burst(hitPosition, "sparks", "#FFD84A")
```

## Forbidden here

No game kinds, no reading the effect back into gameplay (it is cosmetic), no per-hit Instance creation.

## Tests

`tests/features/hitfx/HitFx.test.luau`. The emitter touches the engine: excluded from coverage, unverified until a person checks it in Studio.
