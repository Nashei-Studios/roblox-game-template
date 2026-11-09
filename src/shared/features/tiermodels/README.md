# features/tiermodels

TierModelSet: a tier id maps to a distinct model, material, color set and optional rarity effects, so each tier of a rock, ore or node is recognizable by silhouette and not by tint. Decision: [ADR 0057](../../../../docs/adr/0057-tier-model-set-mold.md). Issue #130. Vault bar W16.

## What it is / is not

- Is: pure Luau (loads under Lune) plus one engine rig. Data-driven config, a model source port with three sources, a silhouette validator, a pool plan, and a `Look` per tier.
- Is not: an asset importer (kits are imported by `assets/kits.manifest.luau`), a spawner (the game decides when a node appears), a collision model (the rig makes parts non-colliding; colliders belong to the game), or art. It never trusts a client.

## Run it locally

```
lune run scripts/test            # TierModelSet suite among the others
lune run scripts/perf-budget     # prints parts and triangles per tier, fails on a clash
pwsh scripts/analyze.ps1
```

## Tree

```
tiermodels/
  TierModelConfig.luau   tiers (recipe, material, colors, rarityId, templateName), silhouette frame; problems(); the default boulder / crystal / cluster
  TierSilhouette.luau    the threshold capture as a function: raster(), overlap(), duplicates(), render()
  TierModelSources.luau  recipes / templates(kit or replicated) / chain / registry over the TierModelSource port
  TierModelSet.luau      look(tierId, quality, surfaceHex): parts with colors, cost, RarityFx spec
  TierPool.luau          pure pool bookkeeping per part shape: capacity, assign, overflow
../../ports/TierModelSource.luau          the port and the part types
../../../client/presenters/world/TierModelRig.luau   engine: fixed pool of parts, template cache, RarityWorldFx
```

Why this split: the config and the silhouette check are data and arithmetic, so the gate (`perf-budget`, tests) catches a clone tier without Studio. The engine appears in one file.

## Design decisions and tradeoffs

- A recipe is the fallback of every source, so a missing kit never leaves a node empty. Cost: a template's silhouette is checked through the recipe as a proxy.
- The silhouette check is conservative (rotated parts use their bounding box, balls an inscribed ellipse). It can reject a pair Studio would accept; it never accepts a clone. Pairs clash only when they overlap in BOTH the front and the side view.
- Triangles per shape are "chosen, not measured" (`TierModelConfig.TRIANGLES`). Measure on the poorest phone before trusting them.
- The pool is built once, per shape. A swap creates no part. RarityWorldFx lights and emitters are re-created only when the rarity id or the quality changes.

## Add a tier or a model

1. Add a `TierSpec` to your config (`Config.default.tierModels.tiers`): id, label, material, three colors, a `rarityId` if it should glow, and a `recipe` built with `TierModelConfig.part(shape, size, offset, role, turn)`.
2. `lune run scripts/perf-budget`: fix any "share a silhouette" or budget line.
3. To use a kit model: set `templateName`, put the `Model` in the kit Package folder or in ReplicatedStorage, and chain `templates("kit", config, TierModelRig.finderFrom(folder, meshPartTriangles))` before `recipes(config)`. Record its license in `assets/kits.manifest.luau`.
4. Draw it with `TierModelRig.new(parent, set, container, options)` and `rig:show(tierId, quality, surfaceHex)`.

## Forbidden here

- Importing a model without a license entry in the kit manifest, or any ripped model.
- Creating parts per tier swap (the pool exists for this).
- Engine calls in the pure files (`TierModelConfig`, `TierSilhouette`, `TierModelSources`, `TierModelSet`, `TierPool`).
- Raising `PerfBudget.tierModels` without measuring on a phone.

## Tests

`tests/features/tiermodels/TierModelSet.test.luau`: duplicate-silhouette rejection (same recipe, recolored copy), shape raster, config problems, look and FX inheritance, the source chain and its fallback, the budget refusal, and "30 swaps create nothing". The rig is not covered by Lune.

## Studio checklist (UNVERIFIED until run)

1. Show each tier on a node; take a capture with the threshold filter; the three silhouettes differ at a glance.
2. `WedgePart` slope: the high end should face +Z; if not, add 180 to its `yawDeg`.
3. Swap tiers 30 times; the Explorer count of the rig folder does not change.
4. Count `BasePart`s per node against `PerfBudget.tierModels`; check frame time on the Device Emulator low phone.
