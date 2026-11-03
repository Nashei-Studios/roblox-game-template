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
5. Studio MCP (optional, see below): bootstrap installs and registers it at user scope; then Assistant > Manage MCP Servers > Enable Studio as MCP server.
6. Check the headless gate passes before writing code: `stylua --check .`, `selene .`, `pwsh scripts/analyze.ps1`, `lune run scripts/test`, `pwsh scripts/coverage.ps1`, `lune run scripts/perf-budget`, `rojo build default.project.json -o places/dev.rbxl`.

## Studio MCP

The MCP proxy built into Studio (`StudioMCP.exe`, signed by Roblox Corporation) is registered at **user scope only** as `Roblox_Studio` ([ADR 0018](docs/adr/0018-studio-mcp-user-scope.md)); there is no project `.mcp.json`, so no second proxy starts. `tools/roblox-studio-mcp.cmd` is the install source: `pwsh scripts/bootstrap.ps1` copies it to `~/.local/bin` and runs `claude mcp add --scope user Roblox_Studio -- cmd.exe /c <that path>` when `claude mcp get Roblox_Studio` fails. The launcher picks the newest `%LOCALAPPDATA%\Roblox\Versions\version-*\StudioMCP.exe` so Studio updates do not break the path. Studio must be open with **Enable Studio as MCP server** turned on (Assistant settings). Check with `claude mcp get Roblox_Studio`: it should list the tools. Use it on a dev or throwaway place only ([ADR 0004](docs/adr/0004-studio-mcp-builtin-only.md)), and only while holding the Studio lock: for Claude Code agents `.claude/hooks/studio-lock` blocks `Roblox_Studio` tools and `rojo serve` without it ([docs/multi-agent.md](docs/multi-agent.md)).

## Folder tree

```
.
├── rokit.toml               pinned toolchain (Rojo, StyLua, Selene, Lune, Luau LSP, Zap)
├── net/schema.zap          remote schema (Zap); output in src/shared/net/generated/ (generated, do not edit)
├── default.project.json     Rojo map; only code folders are managed
├── .luaurc  selene.toml  stylua.toml   strict mode, lint std, format rules
├── .claude/                 Claude Code setup: settings.json (permissions, hook), hooks/studio-lock (Studio lock gate), agents/luau-reviewer
├── .vscode/                 luau-lsp settings and recommended extensions
├── .github/workflows/ci.yml jobs: format, lint, analyze (+ non-blocking new solver), test (PR and push to main)
├── src/
│   ├── shared/              -> ReplicatedStorage/Shared: pure logic, no engine services, Lune-testable
│   │   ├── ports/           types only: what features need from outside (ProfileRepository, Flags, AnalyticsSink, LedgerProvider)
│   │   ├── features/<name>/ one folder per capability (analytics, flags, monetization, playerdata)
│   │   ├── net/             remote helpers: Validation, RateLimiter
│   │   └── perf/            PerfBudget (the numbers), RemoteBudget (static bandwidth), ProbeEvaluator (ADR 0019)
│   ├── server/              -> ServerScriptService/Server
│   │   ├── Main.server.luau the only server Script: composition root
│   │   ├── adapters/        ports implemented over engine services and ProfileStore
│   │   ├── dev/             PerfProbe: Studio-only sampler, off by default (ADR 0019)
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
3. Add `tests/features/<feature>/<Module>.test.luau` and register it in `scripts/suites.luau`.
4. For a remote: validate every argument with `shared/net/Validation` and gate it with a `RateLimiter` (ADR 0012).
5. `stylua .`, `selene .`, `pwsh scripts/analyze.ps1`, `lune run scripts/test`, `pwsh scripts/coverage.ps1`, then open a PR (CI runs the same). Several agents at once: read `docs/multi-agent.md`.

## Start a new game from this template

Preferred: `pwsh scripts/new-game.ps1 -Slug <kebab-case-slug> [-VaultPath <vault>] [-DryRun]`. It validates the slug, runs `gh repo create vruizz22/<slug> --private --template vruizz22/roblox-game-template`, clones into `D:\Victor\Repositoriosoblox\games\<slug>`, renames the game in `default.project.json`, `Config.luau` and this README, writes `games/<yyyy-mm>-<slug>/index.md` in the vault only when `-VaultPath` is given, and prints the names (never values) of `ASPHALT_API_KEY` and `ROBLOX_API_KEY`. `-DryRun` only prints the commands. The template repo must be marked as a template on GitHub first (Victor action, vault decision 0014). Tests: `pwsh scripts/new-game.test.ps1`.

Manual: Use "Use this template" on GitHub once the repo is marked as a template (or copy the folder), rename `name` in `default.project.json`, set `gameName` in `Config.luau`, create game passes and developer products in Creator Hub and fill their ids (each marked `TODO(victor)`), and create a separate dev place for MCP work.

## Game pipeline (short)

Trend note -> scored idea -> game map -> 48-72 h prototype from this template -> title, icon and thumbnails with A/B -> soft launch -> metrics at 72 h: bad = kill and keep the lesson, mixed = iterate, good = scale. The kill verdict is at day 7 (decision D-18 pending).

## Forbidden

No community MCP servers; no secrets in the repo; nothing that moves real money outside a dev place; no `any`; no files without `--!strict`; no dependency or package manager without an ADR; no editing Studio-owned content as files.

## Tests

Pure logic: `tests/` via `lune run scripts/test`; types via `pwsh scripts/analyze.ps1` (both run in CI). Adapters are tested with fakes (`tests/adapters/`); behavior against the real engine has no automated tests yet, the plan is the Open Cloud Luau Execution API once Victor creates the key ([ADR 0005](docs/adr/0005-tests-lune-then-luau-execution.md)).

## Status

Performance budget added 2026-11-03 ([ADR 0019](docs/adr/0019-performance-budget.md), [docs/performance.md](docs/performance.md)): `lune run scripts/perf-budget` fails CI when a remote's worst case passes the budget. The bandwidth numbers are chosen, not sourced; the probe and the Studio procedure have not been run in Studio yet.

Verified locally on 2026-11-02: StyLua, Selene, `luau-lsp analyze` (0 errors), Lune tests and `rojo build`. CI has not run yet (no remote). Still unverified: Studio MCP with several Studios, the engine adapters (no engine tests until the Luau Execution API), and the new-solver pass (informational, reports errors on ProfileStore typing and `os.time` as a clock).

## Remotes (Zap)

Typed remotes are generated from `net/schema.zap` with the Zap CLI pinned in `rokit.toml` ([ADR 0015](docs/adr/0015-remote-layer-codegen.md)). Zap decodes and checks the wire format; the server still rate-limits and validates every remote ([ADR 0012](docs/adr/0012-remote-validation-and-rate-limit.md)).

```powershell
rokit install                           # pins zap too; `rokit trust red-blox/zap` once if asked
pwsh scripts/generate-remotes.ps1       # regenerates src/shared/net/generated/ (CI fails on a diff)
```

How to add an event: [docs/architecture.md](docs/architecture.md#how-to-add-a-remote-event).

## Performance budget

Numbers live in `src/shared/perf/PerfBudget.luau`, each marked sourced (with URL in [docs/performance.md](docs/performance.md)) or chosen, not sourced.

```powershell
lune run scripts/perf-budget    # worst-case bytes/s per remote and per direction; exit 1 over budget
```

Adding a remote means adding its rate to `PerfBudget` (client remotes: the same limit your RateLimiter uses). Dev probe: `perfProbeEnabled` in Config, Studio only. Manual MicroProfiler procedure: [docs/performance.md](docs/performance.md).

## Coverage

Line coverage of the pure Luau code, measured with the Luau CLI ([ADR 0017](docs/adr/0017-luau-coverage-gate.md)):

```powershell
rokit install                      # pins luau and lune (rokit.toml); `rokit trust luau-lang/luau` once if asked
pwsh scripts/coverage.ps1          # runs the suites under `luau --coverage`, writes logs/coverage.lcov, prints the table
```

- The gate is 75 % of the TOTAL lines (`-Threshold` to try another value) and also fails when a file that is not excluded never appears in the lcov (a module no test loads would otherwise hide).
- Excluded: `vendor/`, `types/`, `tests/`, `generated/`, `src/shared/ports/`, `Main.*` and any file that touches `game` (engine code). The report lists every excluded file.
- This is line coverage only (no branches). Tests that need the engine are out of scope until the Luau Execution API job exists (ADR 0005).
- `scripts/suites.luau` is the runtime-neutral runner; `scripts/test.luau` is its Lune entry and `scripts/test_luau.luau` its Luau CLI entry.
