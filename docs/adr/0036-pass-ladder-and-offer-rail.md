# 0036. Pass ladder and offer rail

- Status: accepted
- Date: 2026-11-08
- Deciders: Victor Ruiz
- Refs: referent-features-matrix F20, F21, F22, F33; ADR 0016, ADR 0024

## Context

Every genre read on 2026-11-08 sells a long ladder of multiplier passes with a cheap entry and a high ceiling (Lift Rock 17 passes from 9, Money Per Click 36 passes, Tower Defense Simulator limited-time units) and shows a rotating strip of offers. The template has `monetization` and `pricing` but no notion of tiers, of a starter pack timed after the first minutes, or of an offer rotation.

## Options

| Option | Notes |
|---|---|
| A. Each game hardcodes its passes | Repeats the same stacking bug (x2 and x4 multiplying by accident) and shows stale prices |
| B. Ladder and rail as pure data modules over the existing purchase path | Chosen: no new grant path, so receipts stay idempotent and save-confirmed |
| C. Generate passes through Open Cloud from the config | Prices and creation are Victor's decision (publish step); out of scope |

No external library covers this: it is product logic over `MarketplaceService`, so there is nothing to adopt.

## Decision

Option B. `PassLadder`: tiers ascending by multiplier, `highest` stacking by default (`product` optional), a hard ceiling, a validation against the known pass names, and a check that live base prices ascend with the tiers. `OfferRail`: permanent offers then a rotating window from a caller-supplied index, starter timing by session seconds and account age, hidden when owned or dismissed, and `canPrompt` so the server refuses prompts for offers the player is not shown. Neither module stores a price: they follow ADR 0024.

## Consequences

- Positive: tiers and offers are config; stacking is explicit; a hidden or expired offer cannot be prompted from a forged remote; Lune tests cover the rules.
- Negative: the rail needs the game to pass ownership, session time and account age (`firstJoin` is not yet in `PlayerData`); a presenter and a remote are per game. Limited-time offers need the rotation clock (ADR 0038) or a day number.
- Lost: automatic creation of the passes; price tuning stays a human decision.

## What would change this

Roblox exposing tiered passes natively, or a game needing per-player personalised offers (then the rail becomes a flag-driven experiment, see matrix F50).
