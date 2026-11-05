# ADR 0027: Kit asset manifest, binaries stay in the kit library

- Status: accepted (2026-11-05)
- Date: 2026-11-05
- Refines: ADR 0006 (assets by reference)

## Context

The owner holds third-party kits (UI, icons, food models, sounds, the free RBLX Essentials packs) in a local library at `D:/Victor/Roblox/kits`, outside git. A game stamped from this template needs to know which kits exist, under what terms they may ship, and where Rojo should read them, without committing binaries. Vault decision 0023 routes the free Essentials packs through a persistence shim (issue #34); that shim is not built yet.

## Options considered

| Option | Fit to NFRs | Cost |
|---|---|---|
| A. Manifest in git (Luau data + pure validator), binaries copied on demand into a git-ignored folder | Repo stays small (ADR 0006), license terms are reviewable and tested, Rojo `$path` is known | One more file to regenerate when the library changes |
| B. Git LFS for the kits | Versioned binaries | LFS quota on the free plan; several kits forbid redistribution and this repo is a template that others stamp |
| C. Commit the packs under `vendor/` now | Immediate | The Essentials terms forbid standalone redistribution; pack persistence bypasses `ProfileRepository` until the shim exists (decision 0023), which breaks the "player data only through ProfileRepository" rule |

## Decision

A. `assets/kits.manifest.luau` lists every library kit with `slug`, `version`, `ships`, `sha256`, `license`, `libraryPath` and `rojoPath`. `src/shared/assets/KitManifest.luau` validates it (unique kebab-case slug, 64-hex hash or none, non-empty license, library path under the library root, `rojoPath` present exactly when `ships` is `yes`). The test suite fails when the manifest drifts.

Using a kit in a game: copy it from `libraryPath` into `assets/kits/<slug>` (git-ignored), then point Rojo at it with `"$path": "assets/kits/<slug>"` in the game's own project file. Kits with `ships = no` are references only and have no `rojoPath`.

## Consequences

- Positive: terms and hashes are checked in CI; no binary enters git; the path to use is one string.
- Positive: the free Essentials packs (codes, datastore-purchase, notifications, sound, studded-ui) are listed with their terms ("commercial use in own games allowed, no standalone redistribution"), so no one vendors them by accident.
- Negative: the manifest is generated from the library index and must be regenerated after an intake.
- Negative: the free packs are cataloged but still not wired into a game. They stay out of `vendor/` until the persistence shim (#34) passes its four conditions in decision 0023.

## What would change this decision

Measured need to version binaries (ADR 0006), or a pack license that allows redistribution.
