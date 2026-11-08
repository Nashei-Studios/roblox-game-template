# 0037. Community perk: a lasting percentage for members

- Status: accepted
- Date: 2026-11-08
- Deciders: Victor Ruiz
- Refs: #84, referent-features-matrix F13 and S07; ADR 0026, ADR 0031

## Context

`community-reward` pays coins once. The referents reward membership with a lasting perk: Mine a Mountain "Like and join the group for +1 Digging Luck", Tower Defense Simulator "Join the group for +$100 starting cash". The social module already accepts a `communityPerkPct(userId)` function but nothing in the template produced it.

## Options

| Option | Notes |
|---|---|
| A. Game computes the percentage itself | Each game re-implements the cache and the stale-`false` handling of `IsInGroupAsync` |
| B. `CommunityPerk` in the community-reward folder, behind the `MembershipChecker` port | Chosen: reuses the port and its adapters, pure and testable |
| C. Put the perk in `social` | `social` has no port for membership and no business knowing about groups |

No open-source piece applies: the check is one platform call (`Player:IsInGroupAsync`) already behind the port.

## Decision

Option B. A synchronous `pctFor` reads a cache so it can feed `communityPerkPct` without yielding; `refresh` is the only call to the port. A member answer lasts `membershipTtlSeconds`; a lone `false` does not strip a known member (the platform answer can be stale), a failed check keeps the previous answer; refreshes are rate limited per player and run one at a time. The percentage is validated against a ceiling (`maxPerkPct`) so a typo cannot create a x100 perk. It is never a currency and never Robux.

## Consequences

- Positive: any game gets a real community perk with one config block; the same `SocialPerks` clipping applies on top.
- Negative: the game must call `refresh` on join and from a button; whether rewarding membership is allowed by the platform rules is still an open item (the module ships disabled).
- Lost: a perk that survives the TTL after the player leaves is impossible by design.

## What would change this

An official statement that perks for joining a community are not allowed, or a platform event for membership changes (then `refresh` becomes event driven).
