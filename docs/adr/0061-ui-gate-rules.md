# 0061. UI gate rules: destinations, scroll, motion, button limits and touch locomotion

- Status: superseded by [0071](0071-ui-belongs-to-the-art-owner.md) (2026-11-13)
- Date: 2026-11-09
- Extends: 0039 (automated UI audit), 0045 (spacing and platform-aware controls). Issue #168.

## Context

The owner reviewed game 1 (+1 Mining Power) and listed five defects that passed the gate:

1. In the shops the elements collide while scrolling.
2. About 50 buttons, 4 of them going to the same place.
3. Everything is a list that scrolls down.
4. No animation; nothing feels smooth.
5. Invented mobile buttons (RUN, STOW) that no standard game has.

The audit of ADR 0039 and 0045 measures spacing, clipping, touch size and registration, but it
could not see any of these: it never compared two controls by what they open, never moved a
scroller, never read a menu motion, never counted buttons, and the template itself registered
Sprint and Equip as touch buttons (defect 5, built into the template).

## Options

| Option | Catches | Cost | Verdict |
|---|---|---|---|
| A. Checklist items in the PR template | by eye, what already failed | zero | rejected |
| B. Runtime audit only | all five, in a playtest | needs Studio on every PR; the template has none | insufficient alone |
| C. Pure rules over declarations and measurements in the static gate, plus a runtime collector for what needs layout | all five | one config, one rules module, one config audit | chosen |
| D. One global count of buttons for the whole game | defect 2 | punishes a legitimate 12-offer shop and hides which screen is wrong | rejected |

## Decision

Option C. Limits live in `UiGates` (config, `Config.default.ui.gates`); the rules in
`audit/GateRules` take them as a parameter. A game overrides a limit in its config and records
why in its own ADR.

| Rule | Fails when | Static (`lune run scripts/ui-audit`) | Runtime (`EcoAudit`, playtest) |
|---|---|---|---|
| `UI-DUP-DESTINATION` | two visible controls of one screen and scheme have the same `destination` | the `ControlRegistry` (new field `destination`, per `screen`) | attribute `Destination` or the registry entry |
| `UI-SCROLL-OVERLAP`, `UI-SCROLL-OUTSIDE` | a scroller child overlaps another or leaves the canvas at the start, middle or end of the scroll | layout computed from list order, padding and offset sizes (`StaticRules`) | `AbsolutePosition` read after setting `CanvasPosition` at each sampled offset |
| `UI-MOTION-MISSING` | a modal menu lacks `motion` (open and close tween or spring, hover, press, reduced-motion fallback) or `theme.motionSeconds` is 0 | `ConfigAudit` over `ui.menus` | not measured (declared) |
| `UI-BUTTON-LIMIT` | buttons on a screen exceed the limit for the scheme | registry, per screen and scheme | chrome buttons outside scrolling lists |
| `UI-TOUCH-LOCOMOTION` | a control of a forbidden category (`locomotion`) shows a button on touch | registry | registry |
| `UI-SCROLL-DEPTH` | more scrollers nested than `maxNestedScroll` | ancestors of each `ScrollingFrame` | same |

### Defaults and why

| Key | Default | Reason |
|---|---|---|
| `maxButtons.hud` | touch 6, keyboard 10, gamepad 8 | the thumbs reach two clusters of three on a landscape phone; keyboard has hotkeys so more fit; gamepad reaches by focus but each extra costs navigation. Game 1 had far more |
| `maxButtons.menu` | touch 8, keyboard 12, gamepad 10 | close, tabs and actions of a modal. Rows inside a scroller are content and are not counted: the scroll rules govern them |
| `maxNestedScroll` | 1 | a scroller inside a scroller steals the drag on touch; one level covers every shop and list |
| `tolerancePx` | 1 | the engine rounds sizes and positions |
| `touchForbiddenCategories` | `locomotion` | run is the joystick pushed to the end and stow is a slot of the item bar (the standard recorded as ADR 0076 in the game 1 repo); neither is a button in the Roblox games players know |

Defect 3 (everything is a vertical list) is not a numeric rule. The nested-scroll and
button-limit rules remove the two ways to hide it; the choice of layout stays a design review
item (`roblox-gui` skill).

### Changes to the template found by the new rules

- `LocomotionControls` registered Sprint and Equip as touch buttons. They are now key-only
  (`touchButtons = false` in `LocomotionConfig`): keyboard and gamepad keep their hints, touch
  gets no button. A game that sets `touchButtons` fails `UI-TOUCH-LOCOMOTION` on purpose.
- Modal menus had no declared motion and closed instantly. `MenuShell` now tweens the close
  (skipped under reduced motion) and the four modal menus declare `UiGates.defaultMotion()`.
  Hover and press feedback come from the engine `AutoButtonColor` of `Button`.
- `ControlRegistry` accepts a control with no touch button when it has hints, and gains the
  optional `destination`, `category` and `screen` fields. The item viewer controls declare their
  own screen (`inspect`, `card`) so they do not count against the HUD.

## Consequences

Positive:

- The five defects fail the gate before a screenshot is needed; the registry-level rules run in
  the static gate with no Studio.
- Limits are config, so a genre with a different need changes a value, not the rule.

Negative:

- A control that is not in the registry has no destination, so duplicates are only found among
  registered or `Destination`-tagged buttons (the same premise as ADR 0045: unregistered fails).
- The static scroll layout covers vertical lists and manually positioned children; grids and
  scale-sized rows are left to the runtime audit.
- The runtime half is unverified in the engine until run in a playtest.

What would change this decision: if games keep failing `UI-BUTTON-LIMIT` for legitimate reasons,
the per-screen split gets a per-genre profile instead of a higher global value.
