# features/quests

Daily and weekly quests plus ordered chains, driven by generic counters. Decision: [ADR 0035](../../../../docs/adr/0035-quests-generic-counters-and-chains.md). Issue #56. Matrix rows F08 and F01 in [referent-features-matrix](../../../../docs/referent-features-matrix.md).

## What it is / is not

- Is: pure Luau that loads under Lune. The game feeds named counters from its own server events (`quests:record(userId, "<counter>", amount)`); the module tracks progress, rotates the daily and weekly picks, unlocks chain steps and pays the claim through `ProductGrants` after the save is confirmed.
- Is not: a UI, a dialogue system or an NPC. A "job giver" is a game-side presenter that calls `view` and `claim`. It does not know what a counter means and it never names one.

## Tree

```
quests/
  QuestsConfig.luau   types + validate(): ids, targets, pool sizes, rewards (config, not code)
  Quests.luau         engine: record / claim / view, period rollover, chain steps, rollback
  QuestRequests.luau  ClaimQuest handler: rate limit, then Validation, then claim
```

Why this split: config is data a designer edits, the engine is the only place with rules, the handler is the only place that sees untrusted input (ADR 0012).

## Use from a game

1. Declare quests in your config (`QuestsConfig.QuestsConfig`), call `QuestsConfig.validate` in the bootstrap and refuse to start on problems.
2. Build `ProductGrants.new(Quests.grantTable(config))` and `Quests.new({ config, now = os.time, profileFor, grants, confirmSaved })`.
3. From server game code, call `quests:record(userId, "blocks_broken", 1)` where the event happens. Never from a remote.
4. Add `quests: QuestState?` to `PlayerData` with a migration step (not part of this PR, see the ADR) and send `quests:view(userId)` to the client.
5. Wire one remote to `QuestRequests.handleClaim` with its own `RateLimiter`.

## Rules worth knowing

- Daily pick = deterministic function of the UTC day, weekly pick of the UTC week (7 days from the Unix epoch), so every server agrees. Progress of a rotating pool is cleared when its period key changes; chain progress is kept.
- `maxIncrementPerEvent` refuses an absurd amount from a bug or an exploit; progress caps at the target.
- A claim that cannot be saved is rolled back (coins, claimed flag, chain step) and may be retried.

## Forbidden here

No game vocabulary in names or defaults. No remote that carries progress. No grant outside `ProductGrants`. No `os.time` or engine call: the clock is injected.

## Tests

`tests/features/quests/Quests.test.luau`, registered in `scripts/suites.luau`.
