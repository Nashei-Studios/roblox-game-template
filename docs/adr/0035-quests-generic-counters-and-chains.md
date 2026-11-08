# 0035. Quests with generic counters and chains

- Status: accepted
- Date: 2026-11-08
- Deciders: Victor Ruiz
- Refs: #56, referent-features-matrix F08

## Context

Rock In My Lawn gets 30 to 60 minute sessions from "a new job every few minutes"; most top games of other genres also have daily or weekly objectives. The vault research (referentes ronda 3, gap 1 and 12) asks for a genre-agnostic module: objectives fed by game events, daily and weekly rotation, and chains of jobs.

## Options

| Option | Licence and state | Fit |
|---|---|---|
| A. Adopt `FarFromLittle/Questline` | MIT, 9 stars, pushed 2026-10-07 | Code not read in depth; its objects are Instances and attributes, not a pure core with injected clock and save confirmation. Read for design only |
| B. Adopt `prooheckcp/RoQuest` | Apache-2.0, 20 stars | Not read; same doubt about the save path |
| C. Own pure module over `ProductGrants` and `StreakClock` | n/a | Same reward path as codes and time rewards (ADR 0016), testable under Lune. Chosen |

## Decision

Option C. Quests are data (`QuestsConfig`); progress comes only from server calls to `record(counter, amount)`; the client can only `claim` an id. Daily and weekly picks are a deterministic shuffle of the pool keyed by the UTC day or week. A chain exposes one step at a time. The claim follows ADR 0016: grant, then confirm the save, else roll back.

## Consequences

- Positive: no game vocabulary; every number is config; no remote carries progress; the pick agrees across servers without a store.
- Negative: `PlayerData` has no `quests` field yet, so wiring needs a migration step (the migration chain is ADR 0014) and a Zap remote; both are left to the first game that enables quests. Only coin rewards exist today (`RewardConfig`). The week is 7 days counted from the Unix epoch, not a calendar week.
- Lost: engine-side NPC dialogue; a presenter must be written per game.

## What would change this

A maintained library with a pure core, an injectable clock and a licence we can vendor.
