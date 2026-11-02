# Architecture

## Principle: pure core, thin adapters

Decisions are made by pure modules in `src/shared` (values in, values out, storage injected). Server and client scripts only adapt engine services to those modules. This is the hexagonal split applied to Roblox: ports are Luau types (`Session.Backend`, `Monetization.ReceiptLedger`), adapters are in `src/server`.

```mermaid
flowchart TD
  subgraph Client [Client - StarterPlayerScripts/Client]
    C[Main.client] --> UI[Studio-built UI]
  end
  subgraph Shared [Shared - ReplicatedStorage/Shared - pure, Lune-tested]
    CFG[Config]
    SES[Session lock logic]
    MON[Monetization receipts]
    ANA[Analytics events]
    RES[Result]
  end
  subgraph Server [Server - ServerScriptService/Server - adapters]
    M[Main.server]
    DSB[RobloxDataStoreBackend]
    MS[MonetizationService]
  end
  C --> CFG
  M --> CFG
  M --> SES
  DSB -- implements Backend --> SES
  MS -- ProcessReceipt --> MON
  DSB --> DS[(DataStoreService)]
  MS --> MP[(MarketplaceService)]
```

## Data flow: purchase and save

```mermaid
sequenceDiagram
  participant P as Player
  participant MP as MarketplaceService
  participant MS as MonetizationService
  participant MON as Monetization (pure)
  participant SES as Session (pure)
  participant DS as DataStore
  P->>MP: buys developer product
  MP->>MS: ProcessReceipt(info)
  MS->>MON: processReceipt(ledger, receipt, grant)
  alt PurchaseId already recorded
    MON-->>MS: alreadyGranted
  else grant succeeds
    MON-->>MS: granted (recorded)
  else grant fails
    MON-->>MS: failed (not recorded, Roblox retries)
  end
  MS-->>MP: PurchaseGranted or NotProcessedYet
  Note over MS,DS: On PlayerRemoving the server calls Session.save with release
  MS->>SES: save(backend, key, data, owner, now, true)
  SES->>DS: UpdateAsync (atomic transform)
```

## Tradeoffs

- Pure modules cannot `require` siblings by Roblox instance path and also load under Lune, so they declare a local structural `Result` alias instead of importing `Result.luau`. Cost: a small duplicated type. Benefit: CI tests without Studio.
- The session wrapper is ProfileStore-style but self-written ([ADR 0003](adr/0003-no-package-manager-yet.md): no dependencies). It does not yet handle migrations, session-lock heartbeats or DataStore throttling; add them with tests when a game needs them.
- Engine adapters are untested until the Luau Execution API is wired ([ADR 0005](adr/0005-tests-lune-then-luau-execution.md)).
- The ledger must be persisted inside the player's saved data so "processed" survives server restarts; the template only ships the in-memory ledger.
