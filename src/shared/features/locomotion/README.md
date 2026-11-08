# features/locomotion

Walk, run and tool equip/unequip with a server-owned state. Decision: [ADR 0041](../../../../docs/adr/0041-locomotion-and-tool-controller.md). Issue #88. Matrix rows S02 and S03 in [referent-features-matrix](../../../../docs/referent-features-matrix.md).

## What it is / is not

- Is: pure Luau that loads under Lune. Config validated at bootstrap, a state machine (idle, walking, running, equipped), and a server that validates sprint, equip (ownership, cooldown) and swing (tool in hand, cooldown) and remembers the tool across respawn.
- Is not: a remote (the game adds one, validated per ADR 0012), a combat or mining effect (the game implements `SwingHandler`), an animation set (ids are config; nil keeps the default Roblox animation), a saved loadout.

## Tree

```
locomotion/
  LocomotionConfig.luau   types, default, validate, which animation slots use the Roblox default
  LocomotionMachine.luau  idle / walking / running + equipped; WalkSpeed to apply
  LocomotionServer.luau   per-player machines, equip, swing gate, respawn memory
server/adapters/LocomotionPresenter.luau   MoveDirection in, WalkSpeed out, EquipTool on respawn
client/presenters/LocomotionInput.luau     keyboard and gamepad via ContextActionService
client/presenters/LocomotionHud.luau       touch buttons with the UI system Button
```

## Adopt in a game

1. Set speeds, `sprintMode`, keys and (optionally) animation ids in config; call `LocomotionConfig.validate` at bootstrap.
2. Implement `SwingHandler.swing(playerId, toolId)`: the only place value is granted. Provide `owns(playerId, toolId)`.
3. Build `LocomotionServer.new({ config, now = os.clock, owns, handler })` and `LocomotionPresenter.start({ server, findTool })`.
4. Add three client-to-server remotes (sprint began or ended, equip toggle with a tool id, swing), validate payloads and rate-limit them, and call `server:sprint`, `server:equip`, `server:swing`.
5. On the client call `LocomotionInput.bind` and, on touch, `LocomotionHud.mount` inside the `SafeAreaRoot` content frame.
6. Playtest keyboard, gamepad and touch (not done in the template PR).

## Forbidden here

A client-chosen speed or tool, a hardcoded animation id, game vocabulary in tool ids, raw Frames for the HUD buttons, granting anything outside `SwingHandler`.

## Tests

`tests/features/locomotion/Locomotion.test.luau`, registered in `scripts/suites.luau`.
