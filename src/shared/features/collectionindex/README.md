# features/collectionindex

The CollectionIndex mold: found/total counter, black silhouettes for undiscovered entries, a bar toward a small finite reward and a claim step. Decision: [ADR 0046](../../../../docs/adr/0046-collection-index-mold.md). Issue #128.

## What it is / is not

- Is: a pure model (`CollectionIndex`), a server use case with ports (`CollectionService`) and a UI-system panel (`client/presenters/ui/CollectionIndexPanel`).
- Is not: a catalog, a currency, a reward grant, a remote or a save format. The game owns all of those and plugs them through ports.

## Tree

```
collectionindex/CollectionIndex.luau     types, validate, snapshot, claim decision (pure)
collectionindex/CollectionService.luau   view/claim over DiscoveryPort, ClaimLedgerPort, RewardPort (pure)
client/presenters/ui/CollectionIndexPanel.luau   counter, bar, claim, tabs, grid (engine, thin)
tests/features/collectionindex/          Lune tests
```

## Ports a game adapts

| Port | Meaning |
|---|---|
| `DiscoveryPort.discoveredIds(userId)` | Ids found, derived from persisted data (for example an ore count above 0). Never from a client message. |
| `ClaimLedgerPort` | Claimed milestone ids; `markClaimed` must be durable before the grant; `release` undoes it. |
| `RewardPort.grant` | Gives the milestone `amount`; its meaning is the game's. |

## Adopt in a game

1. Build the `{ Entry }` catalog from game data (group = tab id; `iconRef` = image id).
2. Write the `Config`: tabs, `tabsAboveEntries`, `claimMode`, milestones. Values live in config, never in the panel.
3. `claimMode = "claim"`: add a validated, rate-limited remote (ADR 0012) that calls `CollectionService:claim`, a ledger field in the profile, and add the remote to the perf budget. `"auto"`: no remote; read `snapshot.appliedAmount`.
4. Send `service:view(userId)` to the client and call `panel:setSnapshot`. Pass `renderIcon` for an ItemIcon or ViewportFrame; pass `captionFor` for rarity text; pass your own `labels`.
5. Mount the panel in the body of your menu shell.

## Forbidden here

A currency or game name; trusting the client for discovery; sending the name of an undiscovered entry; a reward value outside config; a hex color or pixel literal in the panel (tokens only); a ViewportFrame per card in the default icon.

## Phone-first

Claim and tab buttons use the 44 px touch floor from the tokens (`Button`, `Parts.tabs`); the grid follows the available width. Opening and closing in one tap, and not covering gameplay, belong to the menu shell the game chooses (`MenuShell` closes with a 44 px button).

## Tests

`tests/features/collectionindex/CollectionIndex.test.luau`, registered in `scripts/suites.luau`. The panel is verified in Studio: 1920x1080, 844x390, 667x375, 568x320.
