# 0034. Visible progression modules: rules, announcer, hit effects, extra board stats, card grid

- Status: accepted
- Date: 2026-11-08
- Deciders: Victor Ruiz
- Origin: plus-one-mining F8 (game PR #71), generalized. Refs #47, #76.

## Context

Building the pickaxe ladder in plus-one-mining produced five pieces any simulator needs: a title by a progress counter, a chat announcement every N units, a hit effect that must not allocate per tap, a daily leaderboard of a counter that profiles do not store, and a grid of cosmetic cards. In the game they carried mining names and numbers (rebirths, meters, taps, pickaxe).

## Options

| Option | Notes |
|---|---|
| A. Leave them in the game | The next game rewrites them and repeats the bugs (announcement spam on join, an emitter per hit). |
| B. Port them with data and templates injected | Rules stay pure under Lune; the engine pieces are thin. Chosen. |
| C. A separate "juice" package | A package manager is not adopted (ADR 0003/0028); a folder per concern is enough. |

For the daily leaderboard there was a second choice. The template boards already support `resetCycle = "daily"`, but the stat list was fixed (`coins`, `sessions`). Options: (1) a new daily-board module, which would duplicate `Leaderboards` and `BoardKey`; (2) an optional `extraStats` list in the config plus an optional `extraFor` dependency, so a game names its own stat and the existing board does the rest. Chosen: (2).

## Decision

Option B, with these shapes:

- `progress/ProgressRules`: `tierFor` over data tiers (`min`, `name`, `colorHex`), `validateTiers`, `milestoneCrossed`, `format` (`{name}` and `{value}` template), `newDailyCounter` (per-UTC-day count from a lifetime counter, in memory).
- `progress/MilestoneTracker`: the first sight of a player is the baseline, so joining high never announces. `server/adapters/Announcer` only delivers a system line through TextChatService; a failure is a `warn`.
- `hitfx/HitFx`: hit kinds are a data table validated for count (cap 40), speed, size, lifetime and glow; `client/presenters/HitFxEmitter` reuses one anchor and one emitter.
- `leaderboards`: `LeaderboardsConfig.extraStats` and an optional `Leaderboards.Deps.extraFor`. A daily board of a game stat is one `extraStats` entry and one `boards` entry; the server returns the value from `extraFor` (for example from `newDailyCounter`).
- `ui/CardGrid` (status, validation, column math, `CardGridPresenter` interface) and `client/presenters/ui/CardGridPanel` built on `Widgets`.

## Consequences

- Positive: no mining vocabulary; every number is config; the pure parts are tested under Lune.
- Negative: the daily counter is in memory, so a rejoin or another server restarts the day at 0 until profiles hold a daily field (same limit as the game). The Announcer and the emitter are engine code, excluded from coverage and unverified until a person runs them in Studio.
- The game's kit-native Wardrobe (clones of the MenuTemplate `Card`) is not ported: the template has no `KitMenus`. A game with a kit implements `CardGridPresenter` over its cards and keeps the model.

## What is lost

Per-game defaults (the game's titles, meters and hit kinds stay in the game as its config).

## What would change this decision

Profiles gaining a persisted daily field (then `newDailyCounter` becomes a reader), or a second game needing a different announcement trigger than a stepped counter.
