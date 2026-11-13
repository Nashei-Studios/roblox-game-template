# Design language

The template draws no UI (ADR 0071): palette, type, spacing, radii, motion and identity of the interface belong to the art owner and live in the game UI system (#214). What stays here is the part the code still enforces: the rarity language.

## Rarity language

Derived for this template: tiers run cold to hot like a metal heating up, so the order reads without the label. Distinct from the amber accent and the status colors. Rarity is never color alone: every tier has a text label. Frames must reach 3:1 on the reference surface `#171C30` (`RarityConfig.referenceSurfaceHex`, checked in `Rarity.test`); a game with another card surface passes its own to `RarityConfig.validate`.

| Tier | Frame | Card tint (top) | Effects |
|---|---|---|---|
| Common | `#9AA5B8` | `#3A4359` | none |
| Uncommon | `#4FD18B` | `#1F4A3A` | glow ring |
| Rare | `#4D8DFF` | `#1F3C78` | glow, shimmer |
| Epic | `#B26BFF` | `#4A2A78` | glow, shimmer, world particles |
| Legendary | `#FF8A3D` | `#7A3A14` | same as Epic |
| Mythic | `#FF4FB8` | `#7A1F5A` | same as Epic |

Locked frame `#3A4260`, neutral: a locked item shows a black silhouette and no rarity color. Effect start tiers, shimmer period (2.4 s), particle rate and the low-quality factor are chosen, not measured; they are config and get measured on a phone.
