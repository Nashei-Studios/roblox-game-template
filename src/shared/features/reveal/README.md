# features/reveal

The reveal moment: a 1.5 to 2.5 s skippable beat that shows an unlocked item large, with its rarity color, light beams, name, rarity label and (for a random source) its odds. [ADR 0054](../../../../docs/adr/0054-reveal-moment-over-the-clip-moment-director.md). Refs #129.

## What it is / is not

- Is: pure Luau that loads under Lune. `RevealMoment.spec` builds what to draw from an `ItemIcon.Item` and the rarity ladder; `momentDef` registers the reveal as a clip moment so `MomentDirector` (ADR 0042) times the sting and the share capture; `session` is the clock (duration, one-tap dismiss, input blocked only while showing).
- Is not: the sting sound, the remote that tells the client an unlock happened, the item catalog, or a 3D viewport. A game supplies those.

## Tree

```
reveal/RevealMoment.luau                        Config, validate, spec, beamCount, oddsText, momentDef, session
tests/features/reveal/RevealMoment.test.luau    registered in scripts/suites.luau
```

## Run locally

`lune run scripts/test`; coverage with `pwsh scripts/coverage.ps1`.

## Adopt in a game

1. `RevealMoment.validate(config, rarityConfig)` at bootstrap (duration inside 1.5 to 2.5, beams under `PerfBudget.clientFx.maxRevealBeams`).
2. Register `RevealMoment.momentDef("reveal_<kind>", config)` with the game's `MomentDirector` config and declare the id in the win-condition `moments` list.
3. On an unlock, the server tells the client over a game remote. The client builds `RevealMoment.spec(config, rarity, { item, random, oddsPercent }, quality, surfaceHex)`; `quality` comes from `RarityFx.qualityFor`.
4. `director:trigger(id)` and `ClipMomentPresenter.run(plan, hooks)` for the sting and capture; the game UI paints the Spec (ADR 0071) and calls `onDone` when it closes.
5. Queue reveals in the game: show one at a time, the next starts in `onDone`.

## Forbidden here

A random item reveal without visible odds (the spec refuses it), a reveal longer than 2.5 s, input blocked after `onDone`, literal colors or spacing numbers in the presenter, a second share prompt path, a beam count above the PerfBudget cap.

## Tests

`tests/features/reveal/RevealMoment.test.luau`.
