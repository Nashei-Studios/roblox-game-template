# features/ui

The pure models and rules that a UI hooks into: `ShopModel`, `CardGrid`, `ItemIcon`, `Contrast`, `InputScheme`, `ControlRegistry` and `MenuController`. Nothing here draws: the template ships no UI kit ([ADR 0071](../../../../docs/adr/0071-ui-belongs-to-the-art-owner.md)) and the game UI (the art owner's system, #214) renders these models through `src/client/presenters/GameUiBridge.luau`. Every module loads under Lune.

## What it is / is not

- Is: data, state and rules a UI needs: what the shop rows say, which cards a player owns, what an icon shows, which controls a scheme needs, which menu is open.
- Is not: a presenter, a theme, a layout or an audit. No Instance is created here and no color, size, font or text for a screen lives here.

## Tree

```
ui/
  ShopModel.luau         shop rows from runtime price quotes; a row without a price cannot be bought
  CardGrid.luau          cards, status line from what the player owns, column math, CardGridPresenter
  ItemIcon.luau          spec of one icon: image, rarity frame, lock silhouette, count or level badge
  Contrast.luau          WCAG contrast ratio of two "#RRGGBB" colors (rarity frames are checked with it)
  InputScheme.luau       touch, keyboard or gamepad, from engine enum names; hint label of a key
  ControlRegistry.luau   each control with its purpose and the schemes that show it; the others get a hint
  MenuController.luau    which menu is open; drives the UiPresenter port (shared/ports)
```

## Attach a UI

1. In `src/client/Main.client.luau` replace the empty mount passed to `GameUiBridge.attach` with your UI. It receives the `Actions` (buy, claim, volume, community) and the `Content`, and returns a `Listener` (coins, shop rows, boards, volumes).
2. Implement the `UiPresenter` port (`setVisible`, `setText`) and pass it, with your menu list, to `MenuController.new`.
3. Build a card grid from `CardGrid` and an icon from `ItemIcon.spec`; paint them with your own components.
4. Register every on-screen control in a `ControlRegistry` so a scheme only shows what it needs.

## Notes

- ItemIcon (ADR 0048, painting half superseded by 0071): `ItemIcon.thumb(assetId, size)` builds an `rbxthumb://` content id (sizes 150 or 420) because `rbxassetid://` of a fresh Image can fail `PreloadAsync` in Studio; `imageUrl` accepts digits, `rbxassetid://` or a ready `rbxthumb://`.
- CardGrid status: owned, then available, else unavailable, with labels from the game ([ADR 0034](../../../../docs/adr/0034-visible-progression-modules.md)).

## Prohibited here

A `UIListLayout`, `ScreenGui` or any other UI Instance; a color, size, font or text literal for a screen; a price written in Config; a client-supplied price or amount.

## Tests

`tests/features/ui/`: `CardGrid.test.luau`, `ItemIcon.test.luau` and `UiModels.test.luau` (contrast, menu controller, shop rows).
