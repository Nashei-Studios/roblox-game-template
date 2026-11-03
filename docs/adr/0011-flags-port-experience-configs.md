# ADR 0011: Flags port over Experience Configs with in-repo defaults

- Status: accepted by recommendation 2026-11-02, revisable
- Date: 2026-11-02
- Source: R1 dev-system research (D-37)

## Context

Live-ops toggles (turn purchases off, tune a number) used to need homemade MemoryStore flags. Experience Configs (`ConfigService`) are first-party: staged and gradual rollout, conditions, history. `GetConfigAsync` returns a point-in-time `ConfigSnapshot` (server only) that must be refreshed.

## Options considered

1. Flags hard-coded in `Config` (no live-ops).
2. A homemade flag store on MemoryStore or DataStore.
3. A `FlagSource` port with an Experience Configs adapter and in-repo defaults as fallback.

## Decision

Option 3. `src/shared/ports/Flags.luau` defines `FlagSource` (`get(name): boolean | number | string?`). `features/flags/Flags.luau` wraps a source (or nil) with typed `getBoolean` and `getNumber` that fall back to `Config.flagDefaults`; a wrong-typed live value is ignored; a flag with no default raises (programming error). `ConfigServiceFlags` is the adapter: it loads the snapshot, refreshes on `UpdateAvailable`, and returns nil if Experience Configs fail to load, so the game still runs on defaults. Every flag must be declared in `Config.flagDefaults`.

## Consequences

- Positive: live-ops without a custom store; the game never depends on the network for flags; the fallback logic is pure and tested.
- Negative: the adapter is engine-only (untested under Lune); Experience Configs limits apply (100 conditions per game, 20 per key, 1,000 active configs); flag values do not change within a read of a stale snapshot until `UpdateAvailable` fires.

## What would change this decision

Roblox changing the `ConfigService` API, or per-player flags becoming common (then add `getForPlayer` on the port, mapped to `GetConfigForPlayerAsync`).
