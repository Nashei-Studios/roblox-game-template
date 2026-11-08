# 0040. Locomotion and tool controller: the server owns the state

- Status: accepted
- Date: 2026-11-08
- Deciders: Victor Ruiz
- Refs: #88, referent-features-matrix S02 and S03, vault ADR 0032 (criterion 5), vault note research/2026-11-08-win-condition.md

## Context

Win-condition criterion 5: walk and run exist, the tool equips and unequips, the first input response is under 2 s. The first frames of a referent clip (Cut a Rock, YouTube NzAc34UfeZ4) show the avatar walking with the tool in hand. The template had an input molde (#75, tap router); the character side was missing. The Roblox default Animate script already plays walk, run and tool poses.

## Options

| Option | Notes |
|---|---|
| A. Client sets WalkSpeed and equips locally | Simple, but a client can send any speed or tool; nothing to test |
| B. Server-owned state machine, client sends intent (chosen) | Sprint, equip and swing are validated (ownership, cooldown) and testable under Lune; the presenter only applies the speed |
| C. Reuse a character-controller library | The candidate from the ecosystem map (NevermoreEngine) has a custom licence and is coupled; nothing needed here is a controller, only state and validation |

## Decision

Option B. `features/locomotion` holds `LocomotionConfig` (speeds, hold or toggle sprint, equipped multiplier, keys, animation ids with nil meaning the default Roblox animation), `LocomotionMachine` (idle, walking, running plus equipped) and `LocomotionServer` (per-player machine, equip with ownership and cooldown, remembered tool across respawn, swing gate that calls a `SwingHandler` the game implements). Presenters stay thin: `LocomotionPresenter` (server) applies WalkSpeed and re-equips; `LocomotionInput` binds keyboard and gamepad with ContextActionService without its touch button; `LocomotionHud` draws the touch buttons with the UI system Button (ADR 0035).

```mermaid
sequenceDiagram
  participant C as Client input
  participant G as Game remote (validated, ADR 0012)
  participant S as LocomotionServer
  participant P as LocomotionPresenter
  C->>G: sprint began / equip toggle / swing
  G->>S: sprint, equip, swing
  S-->>G: verdict (reason on refusal)
  P->>S: setMoving(MoveDirection), speedOf
  P->>P: WalkSpeed = speed; EquipTool on respawn
```

## Consequences

- Positive: speeds and tool grants cannot be forged by a client; the state machine and the gates are tested; animation ids are optional so a game works on defaults.
- Negative: the remote that carries the intent is the game to add (the template ships no remote for it, to avoid dead remotes in the budget); equipped state persists across respawn only in the server session, a saved loadout is the game save; the presenters are unverified in the engine and the keyboard, gamepad and touch playtest of #88 was not run.
- Lost: no dash or block states; a game that needs them extends the machine.

## What would change this

A game needing client-predicted sprint (then speed validation moves to a tolerance check against `speedOf`), or a character controller with a compatible licence that covers state and validation.
