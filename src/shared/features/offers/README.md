# features/offers

Pass ladder (tiered multiplier passes) and offer rail (which offers a player sees, when). Decision: [ADR 0036](../../../../docs/adr/0036-pass-ladder-and-offer-rail.md). Matrix rows F20, F21, F22, F33 in [referent-features-matrix](../../../../docs/referent-features-matrix.md).

## What it is / is not

- Is: pure Luau that loads under Lune. `PassLadder` turns "which passes does the player own" into one multiplier (highest tier or product, clipped to a ceiling) and names the next tier to upsell. `OfferRail` turns session time, account age, ownership and a rotation index into an ordered list of offers.
- Is not: a way to sell or grant anything. Purchases, receipts and `ProcessReceipt` stay in `features/monetization` (ADR 0016). It holds no Robux price either: prices are set in Creator Hub and read at runtime through `PriceLookup` (ADR 0024).

## Tree

```
offers/
  PassLadder.luau  tiers as data, validate, multiplier, nextTier, priceOrderProblems
  OfferRail.luau   offers as data, validate, visible (starter timing, rotation, ownership), canPrompt
```

## Use from a game

1. Declare the passes in `Config.gamePasses` and the packs in `Config.developerProducts`; set their prices in Creator Hub (cheap entry first, high ceiling last, see the matrix).
2. Declare a `PassLadderConfig` and an `OfferRailConfig`; in the bootstrap call `validate` with the sets of names and refuse to start on problems. After the price lookup, call `priceOrderProblems` and log them.
3. Multiply `PassLadder.multiplier(config, owns)` into the rate the game owns (income, luck...). `owns` must read server-side ownership.
4. Show `OfferRail.visible(...)` in the HUD rail with `PriceLabel.format(quote)`. When the client asks to buy, the server calls `OfferRail.canPrompt` first and only then prompts the existing purchase.
5. `rotationIndex` comes from the clock you trust (the `liveops` Rotation of ADR 0038, or a day number).

## Forbidden here

No price literals. No grant, no `ProcessReceipt` handler, no client-supplied ownership. No game vocabulary.

## Tests

`tests/features/offers/Offers.test.luau`, registered in `scripts/suites.luau`.
