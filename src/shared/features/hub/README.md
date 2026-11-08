# features/hub

Central social hub scaffold: where players appear, where the stations live, how many fit. Decision: [ADR 0040](../../../../docs/adr/0040-social-hub-scaffold.md). Issue #87. Matrix rows S01 and S04 in [referent-features-matrix](../../../../docs/referent-features-matrix.md).

## What it is / is not

- Is: pure Luau that loads under Lune. A layout contract (spawn rings, stations as data, server cap, name-tag and emote policy), a registry that gives each player the lowest free slot, and an emote request check. Config-driven, no game names.
- Is not: the place itself (parts, lighting, NPCs are built per game), a menu, an emote animation or a wheel. Menus use the UI system primitives (ADR 0035), never raw Frames.

## Tree

```
hub/
  HubLayout.luau    config types, validate, advise, ring capacity, spawnPoint, stationPosition
  HubRegistry.luau  join / leave / seated, cap, arrive and depart hooks
  HubEmotes.luau    allow-list and per-player cooldown for emote requests
server/adapters/HubSpawner.luau   engine presenter: PivotTo the slot, name-tag distance
```

Why split: layout is geometry and validation, the registry is state, emotes are a policy; each changes for a different reason.

## Server cap guidance

The median server of the 51 games under 90 days with 10k+ CCU (Up-and-Coming, 2026-11-08) is 12; 36 of 51 admit 8 or more; 6 are single-player. One day, one sort, no causality. `HubLayout.advise` warns above 24 players (a crowd hides the avatars the clip must show) and at 1 (declare the game solo in the win-condition checklist). Set the experience max players to the same `serverCap`.

## Adopt in a game

1. Declare a `HubConfig` (id, spawn rings, stations, serverCap, nameTags, emotes) in the game config; call `HubLayout.validate` at bootstrap and refuse to start on problems.
2. Build the hub place so each station sits at `HubLayout.stationPosition` around the hub origin; attach prompts that open menus by `menuId`.
3. On the server, create `HubRegistry.new({ config })` and `HubSpawner.start({ join, leave, origin, nameTagDistance })`.
4. Route emote requests through a validated remote (ADR 0012) and `HubEmotes:request`.
5. Playtest with 2 clients and check that both avatars show (acceptance of #87; not done in this PR).

## Forbidden here

Game names or ids, a position stored outside config, client authority over slots, a station inside the spawn plaza, raw Frames for hub menus.

## Tests

`tests/features/hub/Hub.test.luau`, registered in `scripts/suites.luau`.
