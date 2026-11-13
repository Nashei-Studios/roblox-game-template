# 0063. UI motion kit: pure preset table over native TweenService

- Status: accepted
- Date: 2026-11-09
- Extends: 0061 (UI gate rules). Issue #174.

## Context

The owner said the UI of game 1 had no animation and felt unsmooth. ADR 0061 made motion
mandatory (`UI-MOTION-MISSING`), but the template only tweened the modal scale and gave no shared
vocabulary. The game 2 spec (`docs/ui-spec-game2.md`, vault, section 6) holds a table of motion
with durations; no kit covers UI motion. Rule: nothing from scratch, open source or free only.

## Options

Verified with `gh repo view` and each README on 2026-11-09.

| Option | Licence | Last push | Stars | Install in this template |
|---|---|---|---|---|
| A. spr (fraktality/spr) | MIT | 2024-07-31 | 146 | one 21 KB file, vendorable |
| B. ripple (littensy/ripple) v0.10.2 | MIT | 2026-07-18 | 137 | Wally or npm; monorepo, needs a package manager |
| C. Flipper (Reselim/Flipper) | MIT | 2021-11-25 | 144 | submodule, Wally or rbxm |
| D. Native TweenService plus a thin player over a pure table | engine | n/a | n/a | nothing to install |

| NFR | A. spr | B. ripple | C. Flipper | D. native |
|---|---|---|---|---|
| Mobile performance | one Heartbeat step, native | pure Luau, benchmarks in repo | Luau motors, per-frame callback | engine tweens, no Lua per frame |
| Interruption mid-animation | spring keeps velocity, best | spring keeps velocity | motor keeps velocity | cancel, new tween from current value: no jump, velocity lost |
| Reduced motion | caller | caller | caller | table resolves it (fade only) |
| Size | 21 KB | larger, monorepo | small | 0 KB third party |
| Strict Luau | `--!strict` | typed | partly untyped, 2021 | `--!strict`, ours |
| Toolchain fit (ADR 0003: no package manager) | vendor | needs Wally: breaks ADR 0003 | stale, submodule | fits |

## Decision

Option D. The spec table is timing curves with fixed durations (Quart Out 200 ms, Back Out 160
ms...), which TweenService expresses exactly; a spring would re-tune each value and make the
audit band of +-30 % harder to check. `UiMotion` (shared, pure) holds the table, reduced-motion
resolution and the counter maths and is tested in Lune; `UiMotionPlayer` (client) applies a
preset with TweenService, one tween per instance and property, cancelling and continuing from the
current value. `MenuShell` and `Button` consume it. No third-party code is vendored, so there is
no LICENSE or NOTICE to add.

## Consequences

Positive: zero dependency, the gate-checked table is the source of truth, reduced motion is one
tested function, no change to ADR 0003.

Negative: tweens lose velocity when interrupted (visible only on very fast toggling); no springy
overshoot beyond the Back easing; the player and `MenuShell` wiring are unverified in the engine
until a Studio playtest.

What would change this: if playtests show jumpy interruption or a game wants physical springs,
adopt spr vendored under `vendor/spr` with its LICENSE, behind the same `UiMotionPlayer` API; if a
package manager is adopted later, ripple becomes the candidate.
