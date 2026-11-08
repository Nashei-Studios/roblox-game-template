# features/community-reward

Rewards for members of the game's Roblox community: a one-time coin reward and a lasting perk percentage. Decisions: ADR 0026 (reward), [ADR 0037](../../../../docs/adr/0037-community-perk.md) (perk). Issues #36, #84. Matrix rows F13 and S07 in [referent-features-matrix](../../../../docs/referent-features-matrix.md).

## What it is / is not

- Is: pure Luau that loads under Lune. `CommunityReward` pays a one-time coin reward after a server-side membership check and a confirmed save. `CommunityPerk` keeps a capped percentage perk for members, with a TTL cache, so leaving the community ends the perk.
- Is not: Robux, a currency perk or a client claim. The perk is a number the game multiplies into its own stat (luck, income...). Whether a game may reward membership at all is an open question in the vault research; both modules ship disabled.

## Tree

```
community-reward/
  CommunityRewardConfig.luau  one-time reward config + validate
  CommunityReward.luau        one-time grant (idempotent, rollback on unconfirmed save)
  CommunityRewardRequests.luau remote handler for the one-time check
  FallbackMembership.luau     chains a second MembershipChecker after the first
  CommunityPerk.luau          lasting percentage perk: config, validate, pctFor (sync), refresh (may yield)
```

## Use the perk from a game

1. Set `CommunityPerkConfig` (community id, `perkPct`, `maxPerkPct`, TTL, cooldown); call `CommunityPerk.validate` in the bootstrap.
2. Build `CommunityPerk.new({ config, checker, now })` with the shipped `RobloxGroupMembership` adapter.
3. On player join (and from a "check again" button) call `perk:refresh(userId)`; it may yield, so run it in its own thread. Call `perk:forget(userId)` on PlayerRemoving.
4. Pass `function(userId) return perk:pctFor(userId) end` as `communityPerkPct` to `SocialWiring.start`. It never yields.

## Forbidden here

No Robux amounts. No game vocabulary. No client-supplied membership. No yielding inside `pctFor`.

## Tests

`tests/features/community-reward/CommunityReward.test.luau` and `CommunityPerk.test.luau`, registered in `scripts/suites.luau`.
