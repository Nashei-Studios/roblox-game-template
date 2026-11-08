# features/uisystem

The pure half of the UI system ([ADR 0035](../../../../docs/adr/0035-ui-system-imperative-builders-over-kit-trees.md), guide in `docs/ui-system.md`). Loads under Lune; all of it is covered by `tests/features/uisystem/UiSystem.test.luau`.

## What it is and is not

- Is: the numbers and the rules. Design tokens, device classes and the UIScale policy, safe-area math, the HUD rail planner, construction-time contracts and the kit adapter contract.
- Is not: anything that touches an Instance. The engine builders are in `src/client/presenters/ui/system`. Not the menu state machine either (`features/ui/MenuController`).

## Tree and why

| File | Why it exists |
|---|---|
| `Tokens.luau` | The only place a UI number lives. `validate` rejects a theme that breaks a rule (spacing must grow, touch floor 44, text 12 or more, AA contrast). Key accessors (`space`, `radius`, `typeSize`, `margin`) raise on an unknown key. |
| `Breakpoints.luau` | Device class from the short side, root UIScale (never below 1, 1 on phones), safe margin, modal box. |
| `SafeArea.luau` | Usable rectangle, containment and a clamp for floating pieces. |
| `HudRails.luau` | Plans left, right and bottom rails as geometry: touch-sized tiles, reflow into a second column, a free band for the thumbstick, no overlap, nothing outside the area. |
| `Contracts.luau` | Construction-time checks (gap above 0, 44 px, text bounds, spacing on the scale). The tree-level rules are NOT here: they are `ui/audit/StaticRules`, run by the builders. |
| `KitAdapter.luau` | Contract: slots, required parts per slot, `validate`, `verify` against a tree finder, `uncovered`. |
| `adapters/Studded.luau` | Studded UI Design Only, all seven slots, verified against the real `.rbxm`. |
| `adapters/Plain.luau` | No kit: every slot falls back to a plain piece from the tokens. |

## Design decisions

- Key types are plain strings, not literal unions: the stable solver widens singleton unions in loops and records (ADR 0008). Accessors fail loudly instead.
- The numbers are px at UIScale 1 because the root scale never shrinks, so a 44 px control is at least 44 px on screen.
- The adapter says where parts are, never how they look: kit-native.

## Add a feature

A new rule: add a pure function to `Contracts` (or a new file) with a test, then call it from `DevGuard` or the builder. A new device behaviour: change `Breakpoints` and extend its review-viewport test. A new component: it goes in `presenters/ui/system`, takes `UiEnv`, takes token KEYS, and ends with `DevGuard.verify`.

## Forbidden here

`Instance`, `game`, `Enum`, any require from `src/client`, any literal color or size outside `Tokens.default`, any gameplay value or text.
