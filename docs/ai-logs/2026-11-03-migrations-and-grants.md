# 2026-11-03: migrations, sessionIndex, product grants, adapter tests

## Goal
Ficha R1-T2: D-30 (pure migrations), real `sessionIndex`, D-38 (product delivery) and Lune tests for the engine adapters.

## What was done
- `PlayerDataMigrations` (pure chain, one step per version, golden fixtures v1/v2), schema v2 adds `sessionCount`. ADR 0014.
- `PlayerDataService.join` takes injected `migrate` and `startSession`; on a migration error it releases the lock, exposes nothing and returns the typed error. It returns `{ data, sessionIndex }`; `Main.server` passes the index to `session_start`.
- `ProductGrants` plus a `grant` declaration per `Config.developerProducts` entry (validated in `Config.validate`, duplicate names rejected). `Main.server`'s `grant` now delivers; ids stay `nil`.
- Adapters take their engine service by constructor; `ProfileStoreRepository` and the other two use local structural port aliases. Fake-based tests in `tests/adapters/`.

## Decisions
- `migrateInPlace` writes into the live ProfileStore table (identity must survive); the pure `migrate` never mutates.
- `PlayerDataService` stayed generic: migration and session start are injected hooks, so it does not depend on the PlayerData shape.
- `MAX_COINS = 2^53` (largest exactly representable integer) bounds grants.
- Unknown extra fields survive `migrateInPlace` but are not validated.

## Verification
`stylua --check`, `selene`, `analyze` (0 errors), `lune run scripts/test` (41 -> 72 passed), `rojo build`.

## Open items
- ADR 0011 still says the flags adapter is "untested under Lune"; it is immutable, so this log and `docs/architecture.md` supersede that line.
- `MonetizationService` records the receipt before the grant is saved to DataStore (autosave); consider saving before returning `PurchaseGranted` when real products exist (needs Victor's approval: monetization change).
- Tests against the real engine remain R4 (Execution API key from Victor).
- No GitHub remote yet; nothing pushed.
