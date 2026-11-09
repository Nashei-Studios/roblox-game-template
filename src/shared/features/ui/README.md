# features/ui

Pure model of the UI kit: `UiConfig`, `Layout`, `Contrast`, `MenuController`, `ShopModel` and `CardGrid`. Presenters live in `src/client/presenters/ui`. [ADR 0034](../../../../docs/adr/0034-visible-progression-modules.md) covers `CardGrid`. Refs #47, #76.

## CardGrid

- Is: the data and rules of a grid of cards (a wardrobe, a collection): `Card`, `status` (owned, then available, else unavailable, with labels from the game), `validate`, `columnsFor` (never 0 columns), and the `CardGridPresenter` interface (`refresh(owned)`) a menu talks to.
- Is not: a stat display. Cards show a swatch, a name and a status only.
- Panel: `client/presenters/ui/CardGridPanel` builds it from `Widgets` and theme tokens. A game that has kit cards implements `CardGridPresenter` over them instead.

## Spacing and platform-aware controls (ADR 0045)

- `InputScheme`: touch, keyboard or gamepad, from `Enum.PreferredInput` / `UserInputType` names, plus the hint label of a key.
- `ControlRegistry`: every HUD button with its purpose and the schemes that show it; the others get a hint.
- `audit/EcoRules`, `audit/SourceRules`: the rules that fail a glued list, text flush to a card, a cut label, an unregistered or misplaced control, a raw layout.
- Tests: `tests/features/ui/UiEco.test.luau`. Prohibited: creating a `UIListLayout`/`UIGridLayout` outside the primitive; a gap below the `sm` token.

## Kit-native rule for UI pieces

Never re-tint a kit, and never touch a kit `UIStroke` `Thickness` or `StrokeSizingMode`. `CardGridPanel` paints only the swatch color that the card data gives it.

## Tests

`tests/features/ui/CardGrid.test.luau`; the rest in `tests/features/ui/Ui.test.luau`.
