# features/join

Join architecture: the player never waits for data. [ADR 0032](../../../../docs/adr/0032-join-architecture-data-as-background-state.md). Origin: plus-one-mining PR #60. Refs #47.

## What it is / is not

- Is: pure coordination of a join. `JoinCoordinator` orchestrates, `EntitlementReads` reads in parallel with a deadline, `ProvisionalCredit` bounds the batch of actions taken before the hello, `HelloRetry` is the client retry schedule, `JoinPolicy` holds the `Cancel` callback, the 90 s limit, the guard and the kick texts.
- Is not: the remotes, the loading screen, or a definition of "action". Those belong to the game. Nothing here touches the engine.

## Tree

```
join/
  JoinCoordinator.luau   begin, helloSent, leaving, provisional, forget
  EntitlementReads.luau  readAll(entitlements, readOne, runtime, timeout, onLate)
  ProvisionalCredit.luau claim / commit / abort; cap frozen at the hello by the server clock
  HelloRetry.luau        due(elapsed): 2, 5, 10 s then every 15 s
  JoinPolicy.luau        newWait, guard, kickMessage
```

`features/playerdata/ProfileStoreName.luau` picks the store name (Studio gets its own).

## Use from a game ("actions before the hello")

`ProvisionalCredit` is generic: an "action" is whatever your client does before the hello (taps, clicks). Inject `creditProvisional(userId, count) -> credited`, which sends the count through your normal action path including its validation, and `maxPerSecond`, the most a real player can do in a second. Entitlements are anything read outside the profile (game passes, memberships): inject `readEntitlements`, `applyEntitlements(userId, names, late)` and optionally `onEntitlementsSettled` (pay what a late entitlement adds, idempotently).

Server: `begin` at PlayerAdded, `helloSent` when the profile exists, `leaving` at PlayerRemoving, `forget` afterwards. Client: poll `HelloRetry.due` each frame and send `RequestHello`.

## Not wired in the template yet

Passing `cancel` into `ProfileRepository.load` and the store name into `Main.server` change player data and need approval; see the follow-up issue and PR #72.

## Forbidden here

No engine globals. No `Steal` for a normal load. No write or credit for a player marked `leaving`.

## Tests

`tests/features/join/` (JoinCoordinator with EntitlementReads, HelloRetry and ProvisionalCredit; JoinPolicy) and `tests/features/playerdata/ProfileStoreName.test.luau`.
