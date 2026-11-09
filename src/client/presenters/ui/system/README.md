# presenters/ui/system

The engine half of the UI system ([ADR 0035](../../../../../docs/adr/0035-ui-system-imperative-builders-over-kit-trees.md), guide in `docs/ui-system.md`). It creates Instances, so it is excluded from the line-coverage gate and is **unverified in the engine** until the UI Labs stories are reviewed.

## What it is and is not

- Is: primitives that cannot be built wrong, components skinned by a kit adapter, and a dev guard.
- Is not: game logic, texts, prices or colors of a specific game. It reads `Tokens` and the adapter.

## Tree and why

| File | Why it exists |
|---|---|
| `Atoms.luau` | The few recipes everything is made of: padding and list gap from a token key, text fit, touch floor. |
| `DevGuard.luau` | Runs `StaticRules` over what was just built; raises in Studio, warns once live. |
| `UiEnv.luau` | Tokens, skin, viewport, device class, scale and usable rectangle. Built from a viewport, so stories can fake one. |
| `Skin.luau` | Binds an adapter to a kit tree, verifies it at boot, clones a slot, fixes it structurally (never recolors). |
| `SafeAreaRoot.luau` | The ScreenGui: `CoreUISafeInsets`, scaled frame at `1/scale`, margin padding, content and overlay layers. `layers` builds the same inside any frame. |
| `Stack.luau`, `ScrollList.luau` | Vertical and horizontal stacks, scrolling list, scrolling grid; gap, padding and canvas by construction. |
| `ScrollList.item` | A row with the card padding token, so row text never touches the row edge. |
| `MenuShell.luau` | Modal window: backdrop that swallows input, sized by breakpoint, 44 px close, gamepad focus, scale-only motion. |
| `Button.luau`, `Card.luau`, `Parts.luau`, `Toast.luau`, `OfferCard.luau`, `HudRailsView.luau` | Components. `Parts` holds Badge, CurrencyChip, ProgressBar, Tabs and Tooltip. |

## Design decisions

- Components take `UiEnv` and token keys, never numbers or hex strings.
- A kit slot is cloned and bound by part name; a slot the kit lacks is drawn plain. A component never knows which kit it got.
- Motion animates a `UIScale` only; reduced motion skips it.

## Add a component

1. Take `env: UiEnv.UiEnv` and the parent. 2. Use `Atoms`, `Stack`, `ScrollList` for structure. 3. If a kit piece fits, add a slot to `KitAdapter` (required parts) and clone it with `env.skin:cloneSlot`; else draw it from the tokens. 4. End with `DevGuard.verify(root, name)`. 5. Add it to a scene in `src/client/stories/ui-system/Scenes.luau`.

## Forbidden here

A hex color or a pixel literal that is not derived from `env.tokens` (the one exception is the story harness background); changing a kit color, `UIStroke.Thickness` or `StrokeSizingMode`; a `UIScale` on the ScreenGui; a gameplay value or a user-facing string; skipping `DevGuard.verify`.

## Tests

Pure rules: `tests/features/uisystem/UiSystem.test.luau`. Tree rules: `tests/features/ui/UiAudit.test.luau`. Visual: `src/client/stories/ui-system`.
