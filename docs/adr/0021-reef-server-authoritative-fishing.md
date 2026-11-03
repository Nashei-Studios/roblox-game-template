# ADR 0021: Reef fishing loop is server-authoritative; the bite time is a server secret

- Status: proposed (game-level decision for `2026-11-reef`; Victor has not approved the game)
- Date: 2026-11-03
- Source: design draft `games/2026-11-reef/index.md` in the vault, template ADRs 0009, 0012, 0014, 0015, 0016, 0017, 0019. Numbered 0021 because games 1 and 2 use 0020 on their own branches.

## Context

The game sells fish for coins and coins buy rods that reach deeper, richer water. A client that decides what it caught, how rare it was, or when the bite happened can print coins. The reel timing is the skill element, so it must be judged against a clock the client cannot move. The design also forbids paid random drops, so randomness only comes from play.

## Options considered

### A. Who rolls the catch and judges the reel

| Option | Cheat resistance | Feel | Cost |
|---|---|---|---|
| 1. Client rolls the fish and reports it | None | Best | Lowest |
| 2. Server rolls at cast time and keeps the result; the client only sends Cast and Reel; the server compares its own clock with the bite window | High: the client never sees the fish or the bite time | Reel latency counts against the window | Two small pure modules, a pending-cast table per player |
| 3. Server simulates a reel minigame with a stream of client inputs | High | Richer | Input stream breaks the bandwidth budget (ADR 0019) |

### B. Where the economy lives

| Option | Tunability | Risk |
|---|---|---|
| 1. Prices and fish values hard-coded in server code | Low | A balance change is a code change |
| 2. Zones, fish, rods and prices as data in `ReefConfig`, validated by pure functions | High, unit-tested | A bad table is caught by `ReefConfig.validate`, not at runtime |

## Decision

A2 and B2.

- `FishRoll` (pure) picks a fish from the zone table by weight and a bite delay from a range, using an injected RNG. Bait shortens the delay by a fixed factor; it never changes the weights, so it is not a paid random drop.
- `ReefController` (pure) holds one pending cast per player. `reel` judges `now` (injected clock) against `[biteAt, biteAt + window]`. The first cast of a player with no catches bites within `TUTORIAL_BITE_SECONDS`.
- The client sends `Cast(zone)`, `Reel()`, `Sell()`, `BuyRod()`. The zone is validated against the rod. The server derives prices, values and the stand check; a pass skips the stand check only.
- Player data schema v4 adds `rodLevel`, `bait`, `totalCatches` and `fishStock` (pure step v3 to v4, ADR 0014).
- The Bait pack is a new `ProductGrant` kind (`bait`), bounded by a maximum stock; at the cap the grant is a no-op success, because a failed grant makes Roblox retry the receipt forever (ADR 0016).
- Pass and product ids stay `nil` with `TODO(victor)` in config.

## Consequences

Positive: no client number is trusted; the fish and bite time never leave the server; every remote has a bounded size and rate in `PerfBudget`; the loop, economy and migration run under Lune with coverage.

Negative: network latency eats into the reel window, so the window must be generous and is unmeasured in the engine; the `Bite` message tells the client when to reel, so a script that reels on `Bite` is accepted (that is the game, not a bug, but it means reel timing is a reaction test, not a secret); the pending cast lives in server memory and is lost on a server shutdown, which costs a player one cast; values and weights are unplayed guesses until a playtest; the stand proximity check depends on an engine adapter that cannot be tested headless.

## What would change this decision

Measured auto-reel bots (add a random decoy bite or a cursor minigame, option A3 with a bounded input rate), a playtest showing latency hurts honest players (widen the window or add a server-side latency allowance from ping), or an economy that inflates (adjust the data tables, no code).
