# features/itemslots

The ItemSlots mold: a hotbar of 1 to N slots on the HUD bottom rail, each showing an equipped item with its icon, rarity frame and level or count badge. Decision: [ADR 0055](../../../../docs/adr/0055-item-slots-mold.md). Issue #126.

## What it is / is not

- Is: a pure model (`ItemSlots`), and an `ItemPanel` port. The view is the game UI's.
- Is not: an inventory, the equip logic, a replacement of the Roblox backpack, or the item panel itself. The game owns those.

## Run locally

`lune run scripts/test` (suite `ItemSlots`), `pwsh scripts/coverage.ps1`. Visual check: Studio Device Emulator at 1920x1080, 844x390, 667x375, 568x320.

## Tree

```
itemslots/ItemSlots.luau                    config, slot view, hints, tap, key lookup, registry (pure)
ports/ItemPanel.luau                        open(itemId) port
tests/features/itemslots/                   Lune tests
```

## Adopt in a game

1. Set `Config.itemSlots` (`count`, `keys` per slot as `Enum.KeyCode` names). Validated at boot.
2. Call `ItemSlots.register(registry, config)` once, at bootstrap.
3. Build `{ Entry }` from the equipped items (`ItemIcon.Item` + `ItemIcon.State`) and call `ItemSlots.view(...)`, then `view:render(slots)`.
4. Implement `ItemPanel.open` over your own menu and pass it in `Deps.panel`.
5. Paint the slots with your own UI from the view; the layout (rails, gaps, safe area) is the game UI's.

## Rules

- Hints: keyboard shows the number key, gamepad the pad glyph, touch none. Never a literal key text in the view.
- Slots are registered for all schemes; a new HUD button elsewhere still needs its own entry in the `ControlRegistry`.
- Forbidden: a slot that opens a panel without the port.
