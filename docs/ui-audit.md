# UI audit

The UI quality bar (skill `roblox-barra-visual`, criteria C2 to C14 and the tells list) as two
automated audits. Decision and alternatives: `docs/adr/0050-automated-ui-audit.md`.

| Audit | Runs | Needs | Fails |
|---|---|---|---|
| Static | `lune run scripts/ui-audit` (also in CI and in the gate) | nothing, no Studio | exit 1, one line per finding: rule, file, path |
| Runtime | `AuditRunner` in a playtest, by hand before a PR that touches UI | Studio with the place and Rojo | report with findings; the PR lists them |

## Static audit (gate)

Reads every `assets/ui/**/*.rbxm` with the Lune roblox module and applies
`src/shared/features/ui/audit/StaticRules.luau`.

| Rule | Checks |
|---|---|
| `UI-LIST-PADDING` | a `UIListLayout` inside a `ScrollingFrame`, or with two or more items, has `Padding` above 0 |
| `UI-GRID-PADDING` | a `UIGridLayout` has `CellPadding` above 0 on both axes |
| `UI-SCROLL-CANVAS` | a `ScrollingFrame` has `AutomaticCanvasSize` or the `CanvasUpdater` attribute |
| `UI-SCROLL-PADDING` | a `ScrollingFrame` has a `UIPadding` |
| `UI-TEXT-FIT` | a text is `TextScaled` with a `UITextSizeConstraint`, or carries the `FitHelper` attribute |
| `UI-TOUCH-44` | a button is guaranteed 44 px at the 844x390 reference (size constraint, pixel size or grid cell) |
| `UI-KIT-STROKE` | a `ScaledSize` stroke keeps `Thickness` of 0.2 or less (the kit values, never rewritten) |

The fixes that are not colour live in `tools/ui-restyle.luau` (`fixSpacingAndFit`), so a
re-extraction of the kit (`lune run tools/ui-extract`) reproduces them. Kit colours, gradients and
strokes are never touched (ADR 0047).

## Runtime audit

Layout needs the engine, so this half runs in a playtest.

1. Rojo serving this worktree and connected, `start_stop_play` with `is_start = true`.
2. `execute_luau` with `datamodel_type = "Client"`:

```luau
local Runner = require(game.Players.LocalPlayer.PlayerScripts.Client.presenters.ui.audit.AuditRunner)
local report = Runner.run()
return Runner.summary(report, 12) -- or Runner.toJson(report) to save it
```

3. Stop the playtest.

`AuditRunner.scenarios` opens every modal menu (a clone forced visible) and the HUD. Menus are
cloned into a root Frame of each viewport (844x390, 667x375, 568x320, 1327x496, 1920x1080) plus a
notch pass (844x390 and 667x375 with 47 px side and 21 px bottom insets). The HUD computes its
pixel layout in code from its frame size (`HudLayout`), so it is measured live: the real frame is
resized to each viewport, the presenter lays itself out, and the original size is restored.

| Rule | Checks |
|---|---|
| `UI-OVERLAP` | visible buttons overlap by more than 10 % of the smaller (a button and its transparent hit zone are excluded) |
| `UI-CLIPPED` | a text or button is cut by a clipping parent (the cut of a scroller on its scroll axis is by design) |
| `UI-TEXT-FITS` | `TextFits` is false |
| `UI-OFFSCREEN` | a text or button is less than 98 % inside the screen |
| `UI-SAFE-AREA` | a button is outside the safe rectangle (top bar, notch, home bar) |
| `UI-BUTTON-INERT` | no `AutoButtonColor` and no `PressScale`, or `Active` false on an enabled button |
| `UI-COVERED` | the center of a button or text is under a painting element, or a button sits under its own sibling layer (ZIndex inversion) |
| `UI-LIST-GAP` | siblings of a list or grid are closer than 4 px (two layers on one box are not neighbours) |
| `UI-CONTRAST` | WCAG AA, 4.5 (3 for large text), best of the fill (a gradient multiplies the fill) and the text outline |
| `UI-TOUCH-44` | measured size under 44 px |
| `UI-TEXT-SMALL` | rendered text under 11 px (warning) |

Escape hatches: attribute `AuditIgnore = true` on an element, `StateLess = true` on a button that
has no state on purpose.

### What it cannot do

- `UserInputService.TouchEnabled` and `GuiService` insets are read-only, so the HUD is measured
  with the desktop player list reserved and the notch insets are applied by the runner. The
  `HudLayout` unit tests cover the touch variant.
- Menus are measured as clones: code that reacts to size changes (a signal) does not run in the
  clone. Layout must come from properties.
- A real phone, thumb reach and the exact engine ZIndex stack stay a human check.
- Visual quality (hierarchy, taste) is not measurable here; the screenshots in the PR are.

## Findings of the first run (2026-11-08)

Static: 39 findings in 8 pieces, 0 after the fixes. Runtime (calibrated, five viewports plus the
notch pass): 80 findings before, 3 after (Rebirth at 568x320 only: the two level labels and the
terms need a taller menu than ADR 0037 allows; the standard phone sizes are clean).
