# ADR 0005: Lune for pure logic, Luau Execution API for engine tests

- Status: accepted by recommendation 2026-11-02, revisable
- Date: 2026-11-02
- Source: R0 toolchain research (decisions-proposed.md, D-06)

## Context

Lune runs plain Luau without a DataModel. Jest-Lua last released 2024-12 and runs only inside Roblox. The Open Cloud Luau Execution API is stable (5 min per task, 10 concurrent per place) but needs an API key.

## Options considered

1. Lune for pure logic in CI, plus the Luau Execution API later.
2. Jest-Lua.
3. TestEZ (status unchecked).

## Decision

Option 1. Business logic lives in pure modules (no Roblox services, dependencies injected) so Lune tests it. Engine tests are added when Victor creates the Open Cloud key (stored as a GitHub secret).

## Consequences

- Positive: fast CI with no Studio on the runner; forces a testable core.
- Negative: engine-bound adapters (DataStore, Marketplace) are not covered until the Execution API is wired.

## What would change this decision

Jest-Lua gets active maintenance and a Lune port, or the Execution API quota blocks CI.
