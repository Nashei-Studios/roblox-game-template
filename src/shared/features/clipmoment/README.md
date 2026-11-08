# features/clipmoment

A moment trigger that times the hype and offers one skippable share prompt over CaptureService. Decision: [ADR 0042](../../../../docs/adr/0042-clip-moment-over-capture-service.md) (it holds the Moments feed facts with sources and the open GAPs). Issue #89. Matrix row S12.

## What it is / is not

- Is: pure Luau that loads under Lune. The game declares moments (big break, rare drop, co-op success); `MomentDirector` returns a timed plan: sound sting, camera kick, slow-motion window, screenshot at the peak, share prompt after it. Rate limits (prompt once per session by default, a gap between prompts, an effect cooldown) and two opt-outs (effects, share prompt) live here.
- Is not: the sound (a hook into the sound manager or the music director), the camera rig or slow motion (hooks the game implements), the remote that tells the client a moment happened, or an upload to Moments.

## Tree

```
clipmoment/MomentDirector.luau          config, validate, advise, Director.trigger -> Plan
client/presenters/ClipMomentPresenter.luau   runs a Plan: task.delay per step, CaptureScreenshot, PromptShareCapture
```

## Adopt in a game

1. Declare moments with their beats; call `MomentDirector.validate` at bootstrap and read `advise` (a moment without a sting fails checklist criterion 4).
2. Declare the ids in the game win-condition file (`moments` list, see the win-condition checklist).
3. The server notices the moment (the break, the drop) and tells the client over a game remote.
4. On the client, `director:trigger(id)` and `ClipMomentPresenter.run(plan, hooks)` with `playSting`, `cameraKick`, `setTimeScale` and `launchData`.
5. Add the two settings (effects, share prompt) to the settings menu, built with the UI system.
6. Real capture is checked by hand: a screenshot appears and the share sheet can be dismissed.

## Forbidden here

A prompt without the player seeing it, more than the configured prompts per session, game names in moment ids, a hardcoded sound id, calling CaptureService from the server.

## Tests

`tests/features/clipmoment/MomentDirector.test.luau`, registered in `scripts/suites.luau`.
