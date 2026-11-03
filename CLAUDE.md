# CLAUDE.md

Roblox game template. Strict Luau, Rojo (partially managed), Lune tests. Read `README.md` first.

## Structure
- `src/shared` -> ReplicatedStorage/Shared. Pure logic, loads under Lune: `ports/` (types), `features/<name>/`, `net/`.
- `src/server` -> ServerScriptService/Server. `Main.server` is the ONLY Script (composition root); `adapters/` implement ports over engine services; `features/<name>/` server-only services.
- `src/client` -> StarterPlayerScripts/Client. `Main.client` is the ONLY LocalScript.
- `vendor/` pinned third-party code (ProfileStore) with LICENSE; never edit it. `types/` is data for `analyze`.
- `tests/` mirrors `src`; `scripts/test.luau` runner; `docs/adr/` decisions; `docs/architecture.md` diagrams.

## Commands (run via Rokit tools)
- `stylua .` format, `stylua --check .` verify
- `selene .` lint
- `lune run scripts/test` unit tests (add new suites to the list in `scripts/test.luau`)
- `pwsh scripts/analyze.ps1` type-check (`-NewSolver` for the informational pass)
- `rojo serve` sync to Studio

## Rules
- Every `.luau` file starts with `--!strict`. No `any`. Every exported function has typed params and return.
- Business logic goes in pure modules with constructor-injected `Deps`; engine calls stay in adapters that implement a port. Only `Main.*` builds adapters. No frameworks, no service locators.
- Player data only through `ProfileRepository`; remote arguments only through `net/Validation` and a `RateLimiter`.
- Errors are values (typed Result), never silently swallowed.
- Ids (game passes, products) stay `nil` with `-- TODO(victor): set id` until real. Never invent ids.
- New decision -> new ADR in `docs/adr/`, never edit an accepted one.
- Conventional Commits in English. Everything enters `main` by PR.

## Forbidden
- Community MCP servers; only the Studio built-in MCP (`Roblox_Studio`), and only on a dev/throwaway place.
- Secrets, API keys or tokens in the repo (Open Cloud keys go in GitHub secrets).
- Anything that spends or moves real money; test purchases only on a dev place.
- Editing Studio-owned content through files (world, terrain, UI) or enabling fully managed Rojo without an ADR.
- Adding a package manager or dependency without an ADR.
