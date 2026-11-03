# roblox-game-template

A starting kit for monetized Roblox games: strict Luau, Rojo-synced code, a typed and testable core (config, data sessions, receipts, funnel analytics), lint/format/test in CI, and a Claude Code setup that talks to Studio's built-in MCP.

## What it is and is not

- Is: a template you copy per game. Code lives in Git; the world, terrain and UI are built in Studio ([ADR 0002](docs/adr/0002-rojo-partially-managed.md)).
- Is not: a game, a framework, or a dependency manager setup (no Wally/pesde yet, [ADR 0003](docs/adr/0003-no-package-manager-yet.md)). It contains no real ids, keys or assets.

## Local setup from zero (Windows, PowerShell 7)

1. Install Roblox Studio from roblox.com, log in, enable 2FA. Do not buy Roblox Plus for this.
2. Install Rokit (read `install.ps1` at https://github.com/rojo-rbx/rokit before running it). Open a new terminal. Rokit lives in the default `~/.rokit`.
3. Clone the repo, then from its root: `pwsh scripts/bootstrap.ps1`. It runs the steps below for you and prints OK/FAIL per step. Manual equivalents:
   - `rokit install` (installs the versions pinned in `rokit.toml`)
   - `rojo plugin install`
   - VS Code profile: `code --profile roblox --install-extension JohnnyMorganz.luau-lsp` (repeat for `evaera.vscode-rojo`, `Kampfkarren.selene-vscode`, `JohnnyMorganz.stylua`), then open the folder with `code --profile roblox .`
4. `rojo serve`, open a dev place in Studio, click Connect in the Rojo plugin.
5. Studio MCP (optional, see below): Assistant > Manage MCP Servers > Enable Studio as MCP server.
6. First run formatting once: `stylua .` (the committed files were written without the tool available).

## Studio MCP

`.mcp.json` registers the MCP proxy built into Studio (`StudioMCP.exe`, signed by Roblox Corporation) project-scoped as `Roblox_Studio`, through `tools/roblox-studio-mcp.cmd`, which picks the newest `%LOCALAPPDATA%RobloxVersionsersion-*StudioMCP.exe` so Studio updates do not break the path. Studio must be open with **Enable Studio as MCP server** turned on (Assistant settings). Check with `claude mcp get Roblox_Studio`: it should list the tools. Use it on a dev or throwaway place only ([ADR 0004](docs/adr/0004-studio-mcp-builtin-only.md)).

## Folder tree

```
.
├── rokit.toml               pinned toolchain (Rojo, StyLua, Selene, Lune, Luau LSP)
├── default.project.json     Rojo map; only code folders are managed
├── .luaurc  selene.toml  stylua.toml   strict mode, lint std, format rules
├── .mcp.json                project-scoped Studio MCP registration
├── .vscode/                 luau-lsp settings and recommended extensions
├── .github/workflows/ci.yml jobs: format, lint, analyze (+ non-blocking new solver), test (PR and push to main)
├── src/
│   ├── shared/              -> ReplicatedStorage/Shared: pure logic, no engine services, Lune-testable
│   │   ├── ports/           types only: what features need from outside (ProfileRepository, Flags, AnalyticsSink, LedgerProvider)
│   │   ├── features/<name>/ one folder per capability (analytics, flags, monetization, playerdata)
│   │   └── net/             remote helpers: Validation, RateLimiter
│   ├── server/              -> ServerScriptService/Server
│   │   ├── Main.server.luau the only server Script: composition root
│   │   ├── adapters/        ports implemented over engine services and ProfileStore
│   │   └── features/<name>/ server-only services (MonetizationService)
│   └── client/              -> StarterPlayerScripts/Client: Main.client binds behavior to Studio-built UI
├── vendor/                  pinned third-party code with LICENSE and provenance (ProfileStore)
├── types/                   Roblox definitions for luau-lsp analyze (data only)
├── tests/                   mirrors src, plus a tiny harness and the ProfileRepository port contract
├── scripts/                 test runner, analyze.ps1 and the one-time bootstrap
└── docs/                    roadmap, requirements, milestones, architecture, adr/, multi-agent.md, ai-logs/
```

Why this split: anything that needs only values lives in `shared` so Lune can test it in CI without Studio; anything that touches `DataStoreService` or `MarketplaceService` stays in `server` as a small adapter around a tested core.

## Design decisions and tradeoffs

| Decision | Gain | Cost |
|---|---|---|
| Strict Luau (ADR 0001) | No compile step, native tooling | No TypeScript ecosystem |
| Partially managed Rojo (ADR 0002) | Safe merges | World/UI not in Git |
| Pure core, ports and adapters (ADR 0009) | Lune-testable, no mocks of the engine | A thin adapter per service |
| Local structural `Result` alias in pure modules | They load under Lune without engine `require` paths | Small duplication of the type |
| Idempotent receipt ledger | No double grants | The ledger must persist with player data |

## Add a feature

1. Put the decision and data shape in a pure module under `src/shared/features/<feature>/` with typed exports and a `Deps` table for anything external.
2. If it needs an external service, add a port type in `src/shared/ports` and an adapter in `src/server/adapters`; wire it in `Main.server.luau` (the only place that builds adapters).
3. Add `tests/features/<feature>/<Module>.test.luau` and register it in `scripts/test.luau`.
4. For a remote: validate every argument with `shared/net/Validation` and gate it with a `RateLimiter` (ADR 0012).
5. `stylua .`, `selene .`, `pwsh scripts/analyze.ps1`, `lune run scripts/test`, then open a PR (CI runs the same). Several agents at once: read `docs/multi-agent.md`.

## Start a new game from this template

Use "Use this template" on GitHub once the repo is marked as a template (or copy the folder), rename `name` in `default.project.json`, set `gameName` in `Config.luau`, create game passes and developer products in Creator Hub and fill their ids (each marked `TODO(victor)`), and create a separate dev place for MCP work.

## Game pipeline (short)

Trend note -> scored idea -> game map -> 48-72 h prototype from this template -> title, icon and thumbnails with A/B -> soft launch -> metrics at 72 h: bad = kill and keep the lesson, mixed = iterate, good = scale. The kill verdict is at day 7 (decision D-18 pending).

## Forbidden

No community MCP servers; no secrets in the repo; nothing that moves real money outside a dev place; no `any`; no files without `--!strict`; no dependency or package manager without an ADR; no editing Studio-owned content as files.

## Tests

Pure logic: `tests/` via `lune run scripts/test`; types via `pwsh scripts/analyze.ps1` (both run in CI). Engine-bound adapters have no automated tests yet; the plan is the Open Cloud Luau Execution API once Victor creates the key ([ADR 0005](docs/adr/0005-tests-lune-then-luau-execution.md)).

## Status

Verified locally on 2026-11-02: StyLua, Selene, `luau-lsp analyze` (0 errors), Lune tests and `rojo build`. CI has not run yet (no remote). Still unverified: Studio MCP with several Studios, the engine adapters (no engine tests until the Luau Execution API), and the new-solver pass (informational, reports errors on ProfileStore typing and `os.time` as a clock).
