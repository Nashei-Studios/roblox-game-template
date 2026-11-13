# roblox-game-template

A starting kit for monetized Roblox games: strict Luau, Rojo-synced code, a typed and testable core (config, data sessions, receipts, funnel analytics), lint/format/test in CI, and a Claude Code setup that talks to Studio's built-in MCP.

## What it is and is not

- Is: a template you copy per game. Code lives in Git; the world, terrain and UI are built in Studio ([ADR 0002](docs/adr/0002-rojo-partially-managed.md)). What the team shares live in Studio and what goes through branches: [docs/live-vs-branches.md](docs/live-vs-branches.md).
- Is not: a game, a framework, or a dependency manager setup (no Wally/pesde yet, [ADR 0003](docs/adr/0003-no-package-manager-yet.md)). It contains no real ids, keys or assets.

## Local setup from zero (Windows, PowerShell 7)

1. Install Roblox Studio from roblox.com, log in, enable 2FA. Do not buy Roblox Plus for this.
2. Install Rokit (read `install.ps1` at https://github.com/rojo-rbx/rokit before running it). Open a new terminal. Rokit lives in the default `~/.rokit`.
3. Clone the repo, then from its root: `pwsh scripts/bootstrap.ps1`. It runs the steps below for you and prints OK/FAIL per step. Manual equivalents:
   - `rokit install` (installs the versions pinned in `rokit.toml`)
   - `rojo plugin install`
   - VS Code profile: `code --profile roblox --install-extension JohnnyMorganz.luau-lsp` (repeat for `evaera.vscode-rojo`, `Kampfkarren.selene-vscode`, `JohnnyMorganz.stylua`), then open the folder with `code --profile roblox .`
4. `rojo serve`, open a dev place in Studio, click Connect in the Rojo plugin. Step by step, never the group place: [Test your branch in Studio](docs/live-vs-branches.md#test-your-branch-in-studio).
5. Studio MCP (optional, see below): bootstrap installs and registers it at user scope; then Assistant > Manage MCP Servers > Enable Studio as MCP server.
6. Check the headless gate passes before writing code: `stylua --check .`, `selene .`, `pwsh scripts/analyze.ps1`, `lune run scripts/test`, `lune run scripts/docs-check`, `pwsh scripts/coverage.ps1`, `lune run scripts/perf-budget`, `rojo build default.project.json -o places/dev.rbxl`.

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
├── .github/workflows/ci.yml jobs: check (format, lint, remotes, PR title), analyze (+ non-blocking new solver), test (tests, perf, build, coverage); skipped for drafts and docs-only changes
├── src/
│   ├── shared/              -> ReplicatedStorage/Shared: pure logic, no engine services, Lune-testable
│   │   ├── ports/           types only: what features need from outside (ProfileRepository, Flags, AnalyticsSink, LedgerProvider, SubscriptionPort, AdGateway, ServerContext, PlusPort, RobuxTransferGateway, PriceLookup)
│   │   ├── features/<name>/ one folder per capability (analytics, flags, monetization, playerdata, subscriptions, rewardedads, privateserver, plus, robuxtransfers, pricing)
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
    └── game/                the game design tree: 19 document molds, STAGE, README (ADR 0068); checked by `lune run scripts/docs-check`
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
   Property-based and fuzz tests that try to break the economy, receipts and remotes run in the same command (`lune run scripts/test`); a failure prints its seed, replay it with `{ seed = N }` (see `tests/README.md`, ADR 0062).
4. For a remote: validate every argument with `shared/net/Validation` and gate it with a `RateLimiter` (ADR 0012).
5. `stylua .`, `selene .`, `pwsh scripts/analyze.ps1`, `lune run scripts/test`, `lune run scripts/docs-check`, `pwsh scripts/coverage.ps1`, then open a PR (CI runs the same). Several agents at once: read `docs/multi-agent.md`.

## Engagement modules (codes, time rewards, toasts, sound)

[ADR 0025](docs/adr/0025-engagement-modules.md), implementing ADR 0022. Each is a pure folder under `src/shared/features/` behind one port in `src/shared/ports/`, and every value lives in `Config.default` (`Config.validate` reports each problem).

| Module | Folder | Port | Config key |
|---|---|---|---|
| Promo codes | `features/codes` | `Codes` | `codes` |
| Time rewards | `features/timerewards` | `TimeRewards` | `timeRewards` |
| Notifications | `features/notifications` | `Notifier` (server), `ToastRenderer` (client) | `notifications` |
| Sound | `features/sound` | `SoundSettings` (server), `SoundEngine` (client) | `sound` |

How to add things (all in `src/shared/Config.luau`, then `lune run scripts/test`):

- **A code**: append to `codes.entries` `{ code = "SPRING", reward = { kind = "coins", amount = 100 }, expiresAt = <unix seconds>, maxRedemptions = 1 }`. Matching is case-insensitive; `expiresAt` and `maxRedemptions` (uses per player, default 1) are optional.
- **A daily or session reward**: add a row to `timeRewards.daily` (`day` must be 1..N in order; the streak cycles) or to `timeRewards.sessionGifts` (`id`, `afterMinutes`, `reward`).
- **A toast**: add a key to `notifications.kinds` with `text` (`{amount}` is replaced), `style`, `durationSeconds` and an optional `sound`. A kind the server sends must also be in `NotificationKind` in `net/schema.zap` and in `NotificationsConfig.REQUIRED_KINDS`; then `pwsh scripts/generate-remotes.ps1`.
- **A sound**: add `{ name, assetId, volume }` to `sound.sfx` or `sound.music`. `assetId` stays `nil` with `TODO(victor): set id` until the asset is real; `validate` reports it.

Client wiring: the Studio-built UI calls `net.RedeemCode.fire(text)`, `net.ClaimDailyReward.fire()`, `net.ClaimSessionGift.fire(giftId)` and `net.SetVolume.fire(group, percent)`. Answers come back as `Notify` toasts and `SoundSettings` volumes. The shipped toast renderer is a `SetCore` debug fallback; replace it with a presenter that implements `ToastRenderer` using `UIScale`, safe areas and 44 pt touch targets (`~/.claude/rules/luau.md`, "UI y dispositivos").

Forbidden here: a code, reward, text, duration, volume or asset id written in a script instead of `Config`; a client-supplied amount, time or reward (remotes carry intent only); the client clock for any reward; `ProfileStore` or DataStore calls outside `ProfileRepository`; engine services in `features/`; granting a reward without `ProductGrants`.

## Leaderboards and community reward

[ADR 0026](docs/adr/0026-ui-kit-leaderboards-community-reward.md), implementing ADR 0022 (its UI kit half is superseded by [ADR 0071](docs/adr/0071-ui-belongs-to-the-art-owner.md): the template ships no UI). Each is a pure folder under `src/shared/features/` behind a port in `src/shared/ports/`; every value lives in `Config.default` and `Config.validate` reports each problem.

| Module | Folder | Ports | Config key |
|---|---|---|---|
| Leaderboards (leaderstats, global boards) | `features/leaderboards` | `Leaderboards`, `OrderedBoardStore`, `StatView`, `BoardPublisher` | `leaderboards` |
| Community join reward | `features/community-reward` | `MembershipChecker` | `communityReward` |

- **Attach a UI**: the template draws nothing (ADR 0071). The game UI attaches at the "UI HOOK POINT" of `src/client/Main.client.luau` through `src/client/presenters/GameUiBridge.luau` (actions, content and a listener for coins, shop rows, boards and volumes). Pure models it can reuse live in `src/shared/features/ui`.
- **Add a board**: add `leaderboards.boards.<Id> = { stat, refreshSeconds, size, resetCycle }` (`stat` is `coins` or `sessions`; a new stat goes in `LeaderboardsConfig.STATS` and `PlayerStats.read`). Validation enforces the OrderedDataStore read budget (sum of `60 / refreshSeconds` at most 5). Show a stat next to the name with `leaderboards.leaderstats`.
- **Enable the community reward**: set `communityReward.communityId` and `communityReward.reward` (`{ kind = "coins", amount = n }`), then `enabled = true`. It ships `enabled = false` because rewarding a join is an open [GAP] in the vault research: Victor must confirm the Community Standards and Terms text first.
- **Forbidden here**: a price written in Config or in a presenter; a client write path to a board or a "I joined" message from the client; rewarding likes, favorites or anything in Robux; a client-supplied score; reading the ordered store per join.
- **Tests**: `tests/features/ui`, `tests/features/leaderboards`, `tests/features/community-reward` and `tests/adapters`. The engine lambdas in `Main.server` and `GameUiBridge` need a Studio check.

## Start a new game from this template

Preferred: `pwsh scripts/new-game.ps1 -Slug <kebab-case-slug> [-VaultPath <vault>] [-DryRun]`. It validates the slug, runs `gh repo create vruizz22/<slug> --private --template vruizz22/roblox-game-template`, clones into `D:\Victor\Repositorios
oblox\games\<slug>`, renames the game in `default.project.json`, `Config.luau` and this README, writes `games/<yyyy-mm>-<slug>/index.md` in the vault only when `-VaultPath` is given, and prints the names (never values) of `ASPHALT_API_KEY` and `ROBLOX_API_KEY`. `-DryRun` only prints the commands. The template repo must be marked as a template on GitHub first (Victor action, vault decision 0014). Tests: `pwsh scripts/new-game.test.ps1`.

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

## Monetization surfaces

Subscriptions, rewarded video ads, private servers, the Roblox Plus sign-up prompt and Robux transfers are config-driven modules behind ports (table, diagram, "how to add an item" and the forbidden list: [docs/architecture.md](docs/architecture.md#monetization-surfaces); decisions: ADR 0022 on the `docs/game-systems-adr` branch and [ADR 0024](docs/adr/0024-plus-prompt-robux-transfers-and-runtime-prices.md)).

- Config keys: `subscriptions` (+ `subscriptionPollSeconds`), `rewardedAds`, `privateServers`, `plusPrompt`, `robuxTransfers`. Ads, private servers, the Plus prompt and transfers ship disabled; ids ship `nil`.
- Prices are never literals: read them through the `PriceLookup` port and format with `PriceLabel`. A test fails if `Config.default` holds a price-like number. `privateServers.expectedMonthlyPrice` is the one exception: the platform sets that price in Creator Hub, so it is only an expected value for the release checklist and is never shown.
- Release checklist for these surfaces: set the real ids in Config; compare the Creator Hub private server price with `expectedMonthlyPrice`; turn rewarded ads on only when the experience is eligible (public, 2 thousand monthly unique visitors, ID-verified publisher with 2FA, per the docs); keep transfers off unless the game needs them.
- Forbidden here: granting from a remote or an ad-finished signal, trusting saved subscription status, a literal price in a UI, an engine call outside `src/server/adapters/`.

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
- A game excludes paths it does not own yet (legacy code, generated files) in `gate.config.json`: `analyzeIgnore` for `scripts/analyze.ps1` and CI, `coverageExcludedPrefixes` for the coverage gate. The file belongs to the game and is never synced from the template; `selene.toml` and `.styluaignore` mirror the same paths by hand.
- Excluded: `vendor/`, `types/`, `tests/`, `generated/`, `src/shared/ports/`, `Main.*` and any file that touches `game` (engine code). The report lists every excluded file.
- This is line coverage only (no branches). Tests that need the engine are out of scope until the Luau Execution API job exists (ADR 0005).
- `scripts/suites.luau` is the runtime-neutral runner; `scripts/test.luau` is its Lune entry and `scripts/test_luau.luau` its Luau CLI entry.
