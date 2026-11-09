# features/progress

Visible progression: `ProgressRules`, `MilestoneTracker`, plus the server adapter `server/adapters/Announcer` and the client `presenters/AnnouncementPresenter`. [ADR 0034](../../../../docs/adr/0034-visible-progression-modules.md). Origin: plus-one-mining F8 (PR #71). Refs #47, #76.

## What it is / is not

- Is: pure rules that load under Lune. Tiers (a title and color by a counter such as rebirths), a milestone every N units, a message template, and a per-UTC-day count derived from a lifetime counter.
- Is not: the chat. The server `Announcer` only fires the `AnnounceMilestone` remote; `DisplaySystemMessage` is client-only, so the chat call lives in `Main.client`. It does not know when to speak.

## Rules

- `tierFor(value, tiers)`: the last tier whose `min` is reached. Validate game tiers once with `validateTiers`.
- `milestoneCrossed(previous, current, step)`: the highest multiple of `step` above `previous`; a jump over several bands announces the highest.
- `MilestoneTracker.new(step):observe(userId, value)`: the first sight is a silent baseline (no spam on join); call `forget` on leaving.
- `format("{name} reached {value}!", name, value)`: the text is the game's data.
- `newDailyCounter():observe(userId, lifetime, now)`: units since the first sight of the UTC day. In memory: a rejoin or another server restarts the day at 0.

## Use from a game

```lua
local tracker = MilestoneTracker.new(config.announceEvery)
local daily = ProgressRules.newDailyCounter()
-- when the counter changes:
local reached = tracker:observe(player.UserId, value)
if reached ~= nil then
    announcer:announce(player.DisplayName, reached) -- client formats config.announceText
end
-- daily board: set LeaderboardsConfig.extraStats = { "actionsToday" }, add a board
-- { stat = "actionsToday", resetCycle = "daily", ... } and return actionsToday from
-- Leaderboards Deps.extraFor, computed with daily:observe(userId, lifetimeCounter, os.time()).
```

## Daily leaderboard

No new module: the existing `leaderboards` boards already reset daily (`resetCycle = "daily"`). The one missing piece was a stat the profile does not store, which `extraStats` and `Deps.extraFor` now cover (ADR 0034).

## Forbidden here

No game vocabulary (rebirths, meters, taps), no engine globals in the pure modules, no hardcoded titles or steps: they come in as data.

## Tests

`tests/features/progress/Progress.test.luau`.
