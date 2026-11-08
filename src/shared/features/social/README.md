# features/social

Friend boost, invite reward and the combined perk multiplier. Decisions: [ADR 0030](../../../../docs/adr/0030-social-layer-friend-boost-and-invite.md), [ADR 0031](../../../../docs/adr/0031-invite-ledger-memorystore-and-friend-checks.md). Origin: plus-one-mining PR #62. Issue #52.

## What it is / is not

- Is: pure Luau that loads under Lune. It turns "friends in this server", an optional community percentage and a timed invite boost into one number, `perkMultiplier`, clipped to `maxPerkMultiplier`.
- Is not: a currency, a stat or a UI. The template does not know what the perk is. The game multiplies the number into its own rate (income, luck, damage...).

## Tree

```
social/
  SocialConfig.luau     numbers + problems() validator (config, not code)
  FriendBoost.luau      IsFriendsWith per pair, parallel, cached, O(1) boostPct
  FriendBoostLabel.luau "Friend +N%" text, nil when there is nothing to show
  Referral.luau         LaunchData payload + ReferredByPlayerId validation (200 chars)
  PairKey.luau          unordered pair + UTC day value object (ledger key)
  InviteReward.luau     rules: flag, not self, inviter present, once per pair per day, daily cap
  HashMapLedger.luau    Ledger over a MemoryStore hash map (UpdateAsync claim)
  InviteBoost.luau      timed invite multiplier (session memory, not saved)
  SocialPerks.luau      product of the three, clipped
  SocialRuntime.luau    wires the above with injected effects, retry loop
```

Engine side: `server/adapters/SocialWiring.luau` (Players, HttpService, MemoryStore, task) and `client/presenters/InvitePrompt.luau` (`SocialService`). Neither is covered by Lune; both hold no rules.

## Use from a game

1. In `Main.server`, `SocialWiring.start({ flags, beforeChange, onChanged, communityPerkPct })`; call `onJoin(player)` and `onLeave(player)` from the player events.
2. Multiply `wiring.perksFor(userId).perkMultiplier` into the perk your game owns. In `beforeChange`, settle anything paid at the old rate; in `onChanged`, re-read the rate and push it.
3. Add the Experience Config flag `inviteReward` to your flag defaults. Tune `SocialConfig.default`.
4. Show `FriendBoostLabel.text(friendBoostPct)` in the HUD; bind a button to `InvitePrompt.prompt`.

## Forbidden here

No game vocabulary (power, coins, drill). No grant of currency or Robux from this folder. No DataStore: the ledger is MemoryStore only. No `for ... in` over a table that a yielding call can change.

## Tests

`tests/features/social/` (FriendBoost, FriendBoostLabel, Invite, SocialRuntime), registered in `scripts/suites.luau`.
