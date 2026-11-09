# UI design tokens

Derived for this template (rule: tokens are created from the product domain, never copied from another kit). Every value lives in `Config.default.ui.theme`; a game overrides them there. `UiConfig.validate` checks the contrast pairs and the numeric floors, so a token that breaks them fails `Config.validate`.

Domain: short micro-game sessions, mostly on phones held in one hand, often outdoors. That drives dark, high-contrast surfaces (glare), one warm accent that reads from arm's length, large touch targets and few words per screen.

## Palette

| Token | Value | Reason | Contrast (checked in tests) |
|---|---|---|---|
| background | `#0E1220` | Deep blue-black: the game scene shows through HUD gaps without a flat black slab | base for the pairs below |
| surface | `#171C30` | Panels sit one step above the scene | text on it must pass AA |
| surfaceRaised | `#222945` | Cards, disabled buttons and toast bodies: one more step, not a new hue | text on it must pass AA |
| textPrimary | `#F2F5FF` | Slightly cool white, softer than `#FFFFFF` on dark | at least 4.5 on background, surface and surfaceRaised |
| textMuted | `#B4BCD8` | Secondary text and placeholders | at least 4.5 on surface |
| accent | `#FFB020` | Amber: reads in sunlight, signals "press me", unrelated to the status colors | at least 3 on surface |
| onAccent | `#1B1300` | Text on accent buttons | at least 4.5 on accent |
| success / warning / danger | `#3DDC84` / `#FFD166` / `#FF6B6B` | Toast stripes; status is also in the text, never color alone | at least 3 on surface |
| focus | `#7CC4FF` | Cool blue so keyboard and gamepad focus never looks like the amber accent | at least 3 on surface |

## Geometry and type

| Token | Value | Reason |
|---|---|---|
| radius | 12 pt | Friendly without wasting space on a small screen |
| strokeThickness | 1 pt | Separates surfaces without weight; Studded variant raises it to 2 and squares the corners |
| spacing sm / md / lg | 6 / 12 / 20 pt | A 1 : 2 : 3.3 step, enough to see grouping on a 360 pt wide phone |
| textSize caption / body / title | 12 / 16 / 22 pt | Body 16 stays readable at arm's length; validation refuses body under 14 and caption under 11 |
| font | GothamMedium | Wide, clear digits for prices and scores; any `Enum.Font` name works |
| buttonHeight | 48 pt | Above the floor so a thumb never misses; Layout raises it if the screen scale would drop it under 44 px |
| touchTargetMin | 44 | The project floor (44 pt); validation refuses lower |
| reference | 360 x 640 | The small phone the layout is designed for; larger screens scale up from it |
| scale min / max | 0.75 / 2 | Below 0.75 text is unreadable; above 2 a 1080p screen would waste space |
| panel | 92 % x 84 % of the screen, at most 520 pt wide | Modal fills a phone and stays a column on tablets and desktop |
| motionSeconds | 0.15 | Reserved for open and close transitions: short enough to never block play |

## Behavior rules

- Sizes are `UDim2` scale; points are scaled by one root `UIScale` (`Layout.scaleFor`, same factor in portrait and landscape).
- The `ScreenGui` uses `ScreenInsets.CoreUISafeInsets`: notches and the top bar are respected.
- Touch opens menus from the HUD buttons; keyboard and gamepad toggle them through `ContextActionService` (bindings in `ui.menus`, back in `ui.input`). Nothing depends on hover.
- Prices are never written in Config: the shop shows a placeholder until `GetProductInfoAsync` answers and keeps the buy button disabled without a price.
- Not yet verified by a person: the Device Emulator pass (small phone, tablet, 1080p) and gamepad focus visuals.

## Rarity language

Derived for this template: tiers run cold to hot like a metal heating up, so the order reads without the label. Distinct from the amber accent and the status colors. Rarity is never color alone: every tier has a text label. Frames must reach 3:1 on the surface `#171C30` (checked in `Rarity.test`).

| Tier | Frame | Card tint (top) | Effects |
|---|---|---|---|
| Common | `#9AA5B8` | `#3A4359` | none |
| Uncommon | `#4FD18B` | `#1F4A3A` | glow ring |
| Rare | `#4D8DFF` | `#1F3C78` | glow, shimmer |
| Epic | `#B26BFF` | `#4A2A78` | glow, shimmer, world particles |
| Legendary | `#FF8A3D` | `#7A3A14` | same as Epic |
| Mythic | `#FF4FB8` | `#7A1F5A` | same as Epic |

Locked frame `#3A4260`, neutral: a locked item shows a black silhouette and no rarity color. Effect start tiers, shimmer period (2.4 s), particle rate and the low-quality factor are chosen, not measured; they are config and get measured on a phone.
