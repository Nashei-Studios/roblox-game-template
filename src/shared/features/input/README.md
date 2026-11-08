# features/input

"Tap anywhere": `TapFilter` and `TapRouter`. [ADR 0033](../../../../docs/adr/0033-tap-anywhere-input-router.md). Origin: plus-one-mining PR #59. Refs #47.

## What it is / is not

- Is: pure rules for which input counts as a tap, and a router with input blockers (a modal menu registers one). Loads under Lune: `TapFilter` takes the name of the `UserInputType`, not the enum.
- Is not: the engine binding. The game client script translates `UserInputService` events into `mouseBegan`, `touchBegan`, `touchEnded`, `mouseEnded` and `action`.

## Rules

A press begins a tap only if no GUI took it, it is touch or left mouse, and no blocker is up. A touch counts on release when travel is under 10 px and duration under 0.3 s. The mouse acts on press and can be held. Keyboard and gamepad go through `action`, refused while blocked.

## Use from a game

```lua
local router = TapRouter.new({ tap = onTap, setHeld = onHeld, now = os.clock })
router:addBlocker(function() return menus:anyOpen() end)
```

## Forbidden here

No game vocabulary, no engine globals, no menu knowledge: menus come in through `addBlocker`.

## Tests

`tests/features/input/TapInput.test.luau`.
