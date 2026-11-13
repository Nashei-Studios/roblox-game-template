# features/sharedobjective

A goal everybody in the server pushes at once: it opens on a timer, a shared bar fills, and it ends in a drop or a fail. Decision: [ADR 0049](../../../../docs/adr/0049-shared-objective-mold.md). Source: game 1 Shared Vein and Mega Break, stripped of mining words.

## What it is / is not

- Is: pure Luau that loads under Lune. A state machine with an injected clock, a runtime that ticks it, pays and publishes, and the config that validates the numbers.
- Is not: the reward (the game turns a `Completion` into boost, items or coins in its own sink), the engine loop (the server script calls `step()` once a second), the bar or the banner (a presenter reads the published view), or a goal across servers.

## Tree

```
sharedobjective/
  ObjectiveConfig.luau   typed numbers, neutral defaults, problems()
  SharedObjective.luau   contribute, tick, view; events opened, completed (ranked), failed; beat
  ObjectiveRuntime.luau  step(): tick, reward sink, onCompleted, publish through the port
ports/ObjectivePublisher.luau                     the view the client reads
server/adapters/AttributeObjectivePublisher.luau  attributes of one instance, written on change
```

Why split: the rule changes with design; the clock and players change with the engine; the transport (attributes, remote, StringValue) changes with the game.

## Adopt in a game

1. Copy the defaults and set your numbers; call `ObjectiveConfig.problems(config)` at bootstrap and refuse to start on problems.
2. On the server build `AttributeObjectivePublisher.new({ set = function(n, v) workspace:SetAttribute(n, v) end, prefix = "Objective" })`, then `ObjectiveRuntime.new({ config, publisher, now = function() return workspace:GetServerTimeNow() end, present, reward, onCompleted, onError })`.
3. Run `task.wait(1)` then `runtime:step()` in a loop. Call `runtime:contribute(userId, units)` only from the path that already validated the action (a swing, a kill).
4. In `reward(completion)` pay by `completion.rank` and `completion.top`; return false when the profile is gone.
5. On the client read the attributes (`ObjectiveBeat`, `ObjectiveProgress`, `ObjectiveTarget`, `ObjectiveClosesAt`, `ObjectiveCompleted`) and draw the bar with the game UI. Feed `beat` to the music mood resolver (`features/music`) and `completed` to the clip moment (`features/clipmoment`).

## Forbidden here

A remote that lets a client contribute or read-modify the bar, game words in names (swing, vein, rock), a reward table, engine calls (`game:`, `workspace`) inside the folder, a hardcoded interval.

## Tests

`tests/features/sharedobjective/SharedObjective.test.luau`, registered in `scripts/suites.luau`. It covers config validation, the empty server, the first open, the target that never drops, the rate cap, ranking and ties, the hold of the beat, the missed reward and the attribute adapter.
