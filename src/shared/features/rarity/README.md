# features/rarity

The rarity language: one ladder of tiers and the effects each tier gets. [ADR 0048](../../../../docs/adr/0048-item-icon-and-rarity-language.md). Refs #127.

## What it is / is not

- Is: `RarityConfig` (tier order, colors, effect start tiers, validation), `RarityFx` (spec per tier and quality, quality choice, color mix). Pure, loads under Lune.
- Is not: painting. `client/presenters/rarity/RarityShimmer` (shared clock) and `RarityWorldFx` (light and sparkles on a part) paint; the game UI paints cards.

## Tree

- `RarityConfig.luau`: data and `validate` (frame contrast 3:1 on the surface, particles from Epic up, PerfBudget cap).
- `RarityFx.luau`: `spec`, `lockedSpec`, `qualityFor`, `mix`.
- Tests: `tests/features/rarity/Rarity.test.luau`.

## Run locally

`lune run scripts/test`; coverage with `pwsh scripts/coverage.ps1`.

## Add a tier or change a color

Edit `Config.default.rarity` (tiers keep their array order, commonest first). `Config.validate` fails on a repeated id, a bad hex, a frame under 3:1, or particles below Epic. Keep colors in the DESIGN.md table.

## Quality switch

`RarityFx.qualityFor(config, { setting, graphicsLevel, touch })`. Wire `setting` to a settings toggle ("auto", "high", "low"). Low keeps color, label and glow.

## Prohibited

Literal colors in a presenter; particles below Epic; raising `PerfBudget.clientFx` without a phone measurement; a `ViewportFrame` per card.
