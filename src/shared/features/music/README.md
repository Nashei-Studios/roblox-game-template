# features/music

Playlists by mood, stings on moments, ducking under UI, and a licence manifest, on top of the sound manager. Decision: [ADR 0043](../../../../docs/adr/0043-music-director-and-licence-manifest.md). Issues #90 and #62. Matrix rows E09 and S13.

## What it is / is not

- Is: pure Luau that loads under Lune. `MusicConfig` (licence per sound name, moods, stings per moment kind, duck) and `MusicDirector` (mood, sting, duck, volume write). Audio ids stay in `SoundConfig`; this config only adds who may use them and when they play.
- Is not: a sound engine (the manager and `SoundEnginePresenter` do the playing and the cross-fade), a music player UI (E09 with named tracks and skip is built with the UI system primitives later), or a source of audio ids. Never invent an id; leave `assetId` nil and `validate` says so.

## Tree

```
music/
  MusicConfig.luau    types, validate against SoundConfig, manifest rows
  MusicDirector.luau  setMood, onTrackEnded, sting, duck / unduck, setVolumes, step
```

## Licence basis

`cc0`, `cc_by` (needs an attribution line), `distrokid`, `original`, `roblox_library`. Each entry needs a non-empty source (URL, contract id, library page). The check proves the record exists, not that the claim is true: the owner verifies the source before release.

## Adopt in a game

1. Add the music and sting names to `SoundConfig` with their real ids (a TODO until Victor clears them).
2. Write the `MusicConfig`: one licence per name, moods (lobby, action, event, victory), stings keyed by the `kind` of your clip moments.
3. Call `MusicConfig.validate(config, soundConfig)` at bootstrap and refuse to start on problems.
4. On the client build `MusicDirector.new({ config, sound = soundManager, volumes })`; call `step(dt)` every frame, `setMood` on state changes, `duck("menu")` when a menu opens, and `sting(kind)` from the clip-moment hook `playSting`.
5. Show `MusicConfig.manifest` on a credits screen when any licence is cc_by.
6. Capture a playtest with sound and check the sting starts at or before the moment (not done in the template).

## Forbidden here

An invented or hardcoded asset id, an audio name without a licence entry, writing gains straight to the engine (go through the sound manager), game names in mood ids.

## Tests

`tests/features/music/Music.test.luau`, registered in `scripts/suites.luau`.
