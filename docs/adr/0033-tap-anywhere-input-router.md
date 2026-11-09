# 0033. Tap anywhere: a pure input router with blockers

- Status: accepted
- Date: 2026-11-07
- Deciders: Victor Ruiz
- Origin: plus-one-mining ADR 0038 (tap routing part), generalized.

## Context

Tap games and many simulators act on a tap anywhere on screen. The input rules are subtle and were wrong at first in the game: a touch that drags the camera must not act, a click on a button must not act, an open menu must stop every source (mouse, touch, keyboard, gamepad), and a mouse can be held.

## Options

| Option | Notes |
|---|---|
| A. Each game binds `UserInputService` itself | Duplicates the rules and the bugs. |
| B. Pure `TapFilter` and `TapRouter` fed by a thin engine adapter | Rules testable under Lune; the adapter only translates events. Chosen. |
| C. ContextActionService only | Does not give touch travel and duration; GUI-processed taps are harder to separate. |

## Decision

Option B. `TapFilter` decides from the `UserInputType` name (so it loads under Lune): a press begins a tap only if no GUI took it, it is touch or left mouse, and no blocker is up; a touch counts on release if travel is under 10 px and duration under 0.3 s. `TapRouter` keeps touches per id, holds the mouse, and consults registered blockers (`addBlocker`) before any source acts. A menu registers a blocker; the router never knows menus.

## Consequences

- Positive: one place decides whether input acts; menus opt in without coupling.
- Negative: the engine adapter (UserInputService, ContextActionService) is written per game for now. The thresholds are constants of `TapFilter`.

## What is lost

Per-game tuning without editing the module.

## What would change this decision

A game needing multi-touch gestures or a different tap window (then the constants become configuration).
