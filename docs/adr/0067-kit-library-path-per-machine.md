# 0067. The kit library path is resolved per machine

- Status: accepted
- Date: 2026-11-12
- Supersedes: the `libraryPath` rule of [0027](0027-kit-asset-manifest.md). The rest of 0027 stands.
- Tracking: Nashei-Studios/roblox-game-template#192

## Context

ADR 0027 wrote every `libraryPath` as an absolute path under `D:/Victor/Roblox/kits/`, and the
validator enforced that root. That was true while one person built the games. Since 2026-11-12 the
library is distributed through the studio Drive and every member has a copy at a path of their own
(`studio/docs/primera-vez.md`), on Windows, macOS or Linux. An absolute path in git is wrong for
everyone but its author.

## Options

| Option | For | Against |
|---|---|---|
| A. Keep absolute paths, one manifest per person | No code change | A manifest per person is no longer a shared record |
| B. Force everyone to the same path | One line to change | There is no path valid on the three systems; people already have their libraries placed |
| **C. Relative `libraryPath`, root resolved at use (chosen)** | The manifest is the same for all; the machine supplies the root | One more script; the root must be discoverable |

## Decision

`libraryPath` is relative to the kit library (normally the slug). `KitManifest.validate` rejects an
absolute path and any `..` segment.

`scripts/kit-use.ps1 <slug>` copies a kit into the git-ignored `assets/kits/<slug>`. It finds the
library in this order: `-Library`, the environment variable `NASHEI_KITS`, the `10-kits` entry of
`~/Nashei/puesto.json`, then `~/Nashei/biblioteca/10-kits`. It refuses a kit whose `ships` is `no`.

## Consequences

- For: a member on any system uses the same manifest and one command.
- For: the licence gate (`ships`) is enforced at the moment a kit enters a game folder.
- Against: the manifest no longer says where the files are; `kit-use.ps1 -List` does.
- Not covered: the `lihfolk` plugin path in `.claude/settings.json` is still absolute. Claude Code
  does not expand a variable there; each member edits it in `settings.local.json`.

## What would change this

Packages published as Roblox assets with ids would replace the copy step for kits that may be
uploaded.
