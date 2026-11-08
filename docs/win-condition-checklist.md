# Win condition checklist

Used by every game stamped from this template (vault decision 0032, factory pipeline stages 1, 7, 8 and 12). Evidence and cases: vault note `research/2026-11-08-win-condition` in the roblox-vault repository (no link: the vault is a separate private repository).

The game copy of this file lives in the game notes of the vault (`games/<yyyy-mm>-<slug>/win-condition.md`) or in this repo as `docs/win-condition.md`. Each criterion has a measurable test. A criterion that cannot be tested yet stays `pending`, never `ok` by guess. The thresholds are a proposal and are recalibrated after the first 3 games.

## Hypothesis (stage 1, written before design)

- Hook in one sentence, under 10 words, understandable without playing: ____
- Shareable moment (what a stranger films): ____
- Borrowed channel (a group with its member count, a creator, the Moments feed, other): ____
- 0 to 250 target: owner Victor, date: ____. Roblox gives no threshold.

## Criteria

| # | Criterion | Test | Stage | Result |
|---|---|---|---|---|
| 1 | The hook is visible in the first 3 s of a 9:16 clip | Frames at 0, 1, 2 and 3 s of the captured clip show the hook element (`ffmpeg -vf fps=1`) | 7, 8 | pending |
| 2 | A clip-worthy moment happens within 2 minutes of play | A fresh-profile playtest reaches the moment before 120 s of play, measured with a console timestamp or an analytics event | 7 | pending |
| 3 | Other players are visible on screen, or the game declares itself solo | A playtest with 2 or more clients: the clip has at least 2 avatars. Otherwise the note says `solo` and criterion 6 must be `ok` | 4, 6 | pending |
| 4 | The music fits the declared style | The audio id exists (never invented), its license is noted, the sound moment starts at or before the clip moment, Victor approves the style | 8 | pending |
| 5 | The character feels right | Walk and run exist, the tool equips and unequips, the first input response is under 2 s | 4, 7 | pending |
| 6 | A funny or odd element explains the clip with the sound off | A person who has not seen the game says what is funny (Victor, one test) | 7 | pending |
| 7 | A social reason to bring friends exists | Co-play is rewarded measurably (a bonus that scales with the players present) and the reward is shown at the moment | 4 | pending |
| 8 | The game invites a capture | The share prompt (`PromptShareCapture`) appears after the moment, is skippable and shows at most once per session | 7 | pending |
| 9 | Name and thumbnail promise only what the game has | Roblox limits exposure for mismatched thumbnails; thumbnail rubric G1 passes | 10 | pending |

## Stage 12 measurement (every number with an `as_of` date)

| Metric | Source | Value | as_of |
|---|---|---|---|
| Clips published and channel | Victor | | |
| Peak concurrent players, organic | Creator Dashboard | | |
| Play-through rate, first play bounce | Creator Analytics, Home Recommendations | | |
| D1 and playtime | Creator Analytics | | |
| Visits from Moments | Creator Analytics, if shown | | |

A number that was not read stays blank. The result against the 250 target goes to the post-mortem.

## Declaration in code (checked by Lune)

The hypothesis fields are also declared in `Config.default.winCondition` (type `WinConditionConfig` in `src/shared/features/wincondition/WinCondition.luau`), so a gate can read them:

| Config field | Checklist item | Rule |
|---|---|---|
| `hypothesis` | Hypothesis | Not blank |
| `hookSentence` | Hook in one sentence | At most 9 words (under 10) |
| `shareableMomentIds` | Shareable moment | At least one id, no repeats; empty only with `solo = true`. With the clip-moment module, each id is a declared moment |
| `borrowedChannel` | Borrowed channel | Not blank |
| `funnyElement` | Criterion 6 | Not blank |
| `measurementPlan` | Stage 12 measurement | At least one metric, each with a name and a source, no repeats |
| `targetOwner`, `targetDate` | 0 to 250 target | Owner not blank, date `YYYY-MM-DD` |

`lune run scripts/win-condition` reports what is pending and fails only on a wrong value (the template ships an empty declaration on purpose). `lune run scripts/win-condition --strict` also fails on anything missing: stage 1 closes with it green. The check does not measure anything: the numbers of the stage 12 table stay blank until read, with their `as_of` date.

## Template modules that serve the criteria

| Criterion | Module |
|---|---|
| 3 Other players visible | `features/hub` (spawn plaza, stations, server cap) |
| 5 The character feels right | `features/locomotion` (walk, run, equip) |
| 2, 8 Clip moment and share prompt | `features/clipmoment` |
| 4 Music fits | `features/music` (stings, licence manifest) |
