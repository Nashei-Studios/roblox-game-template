# 2026-11-02: initial template

## Goal
Build the local repository `roblox-game-template` from decisions D-01, D-02, D-04, D-05, D-06 and D-07 of the R0 research. No GitHub remote exists yet; nothing was pushed.

## What was done
- Wrote the toolchain pins, Rojo project, lint/format/strict configs, VS Code files, `.mcp.json`, CI workflow and bootstrap script.
- Wrote the typed core (`Config`, `Session`, `Monetization`, `Analytics`, `Result`) and thin server/client adapters.
- Wrote Lune tests, a runner, 6 ADRs and the project docs.

## Decisions
See `docs/adr/0001` to `0006` (all "accepted by recommendation 2026-11-02, revisable").

## Verification
Static only: JSON/TOML parse, `--!strict` header check, typed-export check. No tool (Studio, Rokit, Rojo, Lune, StyLua, Selene) was installed, so tests, format and lint have NOT been run.

## Open items
- Run `scripts/bootstrap.ps1`, `stylua .`, `selene .`, `lune run scripts/test`.
- Confirm the `CompeyDev/setup-rokit` action tag, the `mcp.bat` path, and Lune's resolution of `*.test` requires.
- Victor creates the private GitHub repo `vruizz22/roblox-game-template`, then pushes the branch and opens a PR.
