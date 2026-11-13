# 0071. UI belongs to the art owner; the template ships no UI kit

- Status: accepted
- Date: 2026-11-13
- Deciders: Victor Ruiz (decision of 2026-11-13)
- Supersedes: [0035](0035-ui-system-imperative-builders-over-kit-trees.md), [0039](0039-automated-ui-audit.md) (the UI audit; not the gitflow ADR with the same number) and [0061](0061-ui-gate-rules.md); and the painting half of [0048](0048-item-icon-and-rarity-language.md) and of [0045](0045-ui-spacing-and-platform-aware-controls.md). Refs #214, #225.

## Context

UI, UX, art, icon and thumbnails of every game belong to Leon. The template shipped its own UI system anyway: imperative builders, a skin layer, design tokens, a dev guard, a static and a runtime audit, UI Labs stories and three guides. Agents built it with emoji icons and engine defaults, so it never carried the identity of a game, and a game that wanted Leon's UI had to dismantle it first (drain-for-loot did, its ADR 0067). Issue #214 adopts the UI system Leon built in the legacy games as the template's UI base. Two UI systems in one template is the worst case: the games inherit both and the agents keep extending the one that is not the owner's.

NFRs: no duplicated ownership of the look; the rules that are not visual (what is bought, what rarity is, what a slot holds) stay tested and reusable; the gate stays fast and green; a game attaches its UI without touching remotes or Config.

## Options evaluated

| Option | Look owned by | Reusable logic kept | Gate cost | Migration for games |
|---|---|---|---|---|
| A. Keep the kit as a default skin under Leon's system | Agents | Yes | Static audit and runtime audit stay | None, but two systems coexist |
| B. Move the kit to an optional package | Agents | Yes | Package gate to maintain | Games opt in; nobody does |
| C. Remove everything that draws and keep the models, state, events and remotes | The art owner | Yes, in `src/shared` | Smaller | Games already off the kit lose nothing |

## Decision

**Option C.** The template ships no UI. Removed: `src/client/presenters/ui/**` (UiKit, Widgets, system, audit, panels and views), `LocomotionHud`, `RevealMomentPresenter`, the UI Labs stories, `features/uisystem`, `features/ui/{UiConfig,UiGates,Layout,audit}`, `Config.default.ui`, `scripts/ui-audit` and `scripts/ui-adapter-check` with the CI step "UI audit (static)", and the guides `docs/ui-system.md`, `docs/ui-audit.md` and `docs/ui-kit-intake.md`.

Kept in `src/shared`, because each is a model or a rule and none draws: `ShopModel`, `CardGrid`, `ItemIcon` (the spec of an icon: image, rarity frame, lock, badge), `Contrast`, `InputScheme`, `ControlRegistry`, `MenuController` with the `UiPresenter` port, the rarity rules, `CollectionIndex`, `ItemSlots`, `InspectView`, `LocomotionControls` and `RevealMoment`. `MenuController` now owns the two-field `MenuConfig` it needs, and `ControlRegistry` owns the control categories; both used to import them from the removed config. `InputSchemeWatcher` (it reads the engine input, creates nothing) moved up to `src/client/presenters/`.

The hook: `src/client/presenters/GameUiBridge.luau` turns remotes, shop prices and board replication into `Actions`, `Content` and a `Listener`. `Main.client.luau` mounts no UI and calls `GameUiBridge.attach` at its "UI HOOK POINT" with an empty mount; a game replaces that mount with its UI. Toasts keep the SetCore renderer until the game supplies its own.

`RarityConfig.referenceSurfaceHex` replaces the card surface that was read from the UI theme when `Config.validate` checks frame contrast; a game with another surface passes its own to `RarityConfig.validate`.

## Consequences

- Positive: one owner for the look; no agent can extend a second UI system; the gate and the CI lose the audit step and the code, tests and docs of the kit (about 9,900 lines removed in this change); games get a documented, typed attach point.
- Negative, said plainly: the template has no visible UI at all until Leon's system lands (#214), so a fresh template place shows only the SetCore toasts. The static and runtime UI audits and their rules (button limits, scroll depth, motion, text fit, 44 pt floor, spacing) are gone, and nothing replaces them yet: Leon's system must bring its own checks or a later ADR restores some of them. The Device Emulator review is back to a manual step. The dev guard that stopped raw `Instance.new` in presenters is gone. Pure tests of the removed layout, tokens and audit rules were deleted with their modules, so total test count and line coverage of `src/shared` changed.
- What would change this: Leon's system not covering a rule the audits enforced, or two games needing the same non-visual check that Leon's system lacks. The first case is a new ADR that ports that single rule; the removed code stays in git history before the release that carries this ADR.

## Follow-up

- Games that still carry the kit remove it as drain-for-loot did; the template sync and a release follow, outside this change.
- The join probe mark `uiKit` (time until the HUD is ready) is renamed `ui`, and its log key `uiKitS` is `uiS`, so no kit name survives; a collector that reads the old key must follow.
