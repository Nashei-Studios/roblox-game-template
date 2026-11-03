# Architecture

## Principle: pure core, ports, thin adapters

Decisions are made by plain Luau modules with constructor dependency injection ([ADR 0009](adr/0009-plain-modules-constructor-di.md)). No framework (Knit and Roact are archived). Features depend on **ports**: Luau types that describe an external service. **Adapters** implement ports over engine services or vendored libraries. One Script per side (`Main.server`, `Main.client`) is the composition root: the only place that builds adapters and wires events.

Ports (all in `src/shared/ports`, types only):

| Port | What it hides | Production adapter | Test double |
|---|---|---|---|
| `ProfileRepository` | player data with session locking | `ProfileStoreRepository` (ProfileStore, [ADR 0010](adr/0010-profilestore-behind-profilerepository.md)) | `InMemoryProfileRepository` |
| `Flags` (`FlagSource`) | live-ops flags | `ConfigServiceFlags` (Experience Configs, [ADR 0011](adr/0011-flags-port-experience-configs.md)) | a table-backed source |
| `AnalyticsSink` | funnel event delivery | `AnalyticsServiceSink` (`LogCustomEvent`) | a recording sink |
| `LedgerProvider` | per-player purchase ledger (monetization) | built in `Main.server` from the player's profile | a table ledger |

```mermaid
flowchart TD
  subgraph Client [Client - StarterPlayerScripts/Client]
    CM[Main.client - only LocalScript] --> UI[Studio-built UI]
  end
  subgraph Shared [Shared - ReplicatedStorage/Shared - pure, Lune-tested]
    CFG[Config]
    subgraph Features [features/*]
      PD[playerdata: PlayerData, PlayerDataService]
      MON[monetization: Monetization]
      ANA[analytics: Analytics, AnalyticsTracker]
      FLG[flags: Flags]
    end
    subgraph Ports [ports/* - types only]
      P1[ProfileRepository]
      P2[Flags]
      P3[AnalyticsSink]
      P4[LedgerProvider]
    end
    NET[net: Validation, RateLimiter]
    FAKE[InMemoryProfileRepository]
  end
  subgraph Server [Server - ServerScriptService/Server]
    SM[Main.server - only Script, composition root]
    subgraph Adapters [adapters/*]
      A1[ProfileStoreRepository]
      A2[ConfigServiceFlags]
      A3[AnalyticsServiceSink]
    end
    MS[features/monetization/MonetizationService]
  end
  VEN[(vendor/ProfileStore)]
  CM --> CFG
  SM --> A1 & A2 & A3 & MS
  SM --> PD & FLG & ANA
  A1 -- implements --> P1
  A2 -- implements --> P2
  A3 -- implements --> P3
  FAKE -- implements --> P1
  PD --> P1
  FLG --> P2
  ANA --> P3
  MS --> P4
  MS --> MON
  A1 --> VEN
  VEN --> DS[(DataStoreService)]
  A2 --> CS[(ConfigService)]
  A3 --> AS[(AnalyticsService)]
  MS --> MP[(MarketplaceService)]
```

Dependency direction: `adapters -> ports <- features`. A feature never requires an adapter or an engine service. `src/shared` never requires `src/server`.

## Folder structure (why each level)

```
src/
  shared/                    -> ReplicatedStorage/Shared. Loads under Lune: no engine services.
    Config.luau  Result.luau   typed config; typed Result
    ports/                   types only: what features need from the outside world
    features/<feature>/      one folder per capability; the template stays genre-agnostic
    net/                     remote helpers: Validation, RateLimiter (ADR 0012)
  server/                    -> ServerScriptService/Server
    Main.server.luau         the ONLY server Script; builds adapters, injects, connects events
    adapters/                implementations of ports over engine services / vendored libs
    features/<feature>/      server-only services (need engine services, e.g. MonetizationService)
  client/                    -> StarterPlayerScripts/Client
    Main.client.luau         the ONLY LocalScript; binds behavior to Studio-built UI
vendor/                      pinned third-party code with LICENSE and provenance (ProfileStore)
types/                       Roblox definitions for luau-lsp analyze (data, ADR 0007)
tests/                       mirrors src: tests/features/<feature>, tests/net; harness.luau
```

## Data flow: join, purchase, leave

```mermaid
sequenceDiagram
  participant P as Player
  participant SM as Main.server
  participant PDS as PlayerDataService
  participant R as ProfileRepository (ProfileStore)
  participant MP as MarketplaceService
  participant MS as MonetizationService
  participant MON as Monetization (pure)
  P->>SM: PlayerAdded
  SM->>PDS: join(userId)
  PDS->>R: load(key) (yields, session lock)
  alt session unavailable
    R-->>PDS: error session_unavailable
    SM-->>P: Kick (rejoin)
  else loaded
    R-->>PDS: handle (data.purchases = ledger)
  end
  P->>MP: buys developer product
  MP->>MS: ProcessReceipt(info)
  MS->>PDS: ledgerFor(userId) via LedgerProvider
  alt data not loaded
    MS-->>MP: NotProcessedYet (Roblox retries)
  else PurchaseId already recorded
    MON-->>MS: alreadyGranted
  else grant succeeds
    MON-->>MS: granted (recorded in the profile)
  else grant fails
    MON-->>MS: failed (not recorded, Roblox retries)
  end
  P->>SM: PlayerRemoving
  SM->>PDS: leave(userId)
  PDS->>R: handle.release() (final save, lock released)
```

## Tradeoffs

- **Types duplicated across ports and features.** Modules that must load under Lune cannot `require` siblings by Roblox instance path, so each declares a small local structural alias (`Result`, `ProfileHandle`). Cost: duplication, kept honest by the compiler (a structural mismatch fails `analyze`). Benefit: CI tests without Studio.
- **Ports live in `shared`, not `server`.** The research placed ports in `server/ports`. We keep them in `shared/ports` so pure feature services and tests can name the port types without engine paths. The client ignores them. Cost: server-only contracts are visible to the client's `Shared` folder (types only, no code).
- **ProfileStore is vendored, not rewritten** ([ADR 0010](adr/0010-profilestore-behind-profilerepository.md)): one more third-party file to audit and bump, in exchange for a battle-tested session lock. The port limits the blast radius if it is replaced.
- **Adapters are tested with fakes under Lune; the real engine is not** ([ADR 0005](adr/0005-tests-lune-then-luau-execution.md), [ADR 0009](adr/0009-plain-modules-constructor-di.md)). Each adapter takes its engine service by constructor (`tests/adapters/`), so the translation logic is covered; behavior against the real services and ProfileStore waits for the Luau Execution API. The port contract test (`tests/features/playerdata/ProfileRepository.contract.luau`) is ready to run against the real adapter.
- **`Profile:Save()` is asynchronous** in ProfileStore, so `handle:save()` returns ok once the save is scheduled; failures arrive through `ProfileStore.OnError` (to wire per game).
- **Migrations are a pure chain, not ProfileStore hooks** ([ADR 0014](adr/0014-pure-migration-chain.md)): `PlayerDataService.join` runs `PlayerDataMigrations.migrateInPlace` before exposing data; a newer-schema profile fails the join instead of being downgraded.
