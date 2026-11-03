# ADR 0010: ProfileStore (vendored) behind a typed ProfileRepository port

- Status: accepted by recommendation 2026-11-02, revisable
- Date: 2026-11-02
- Source: R1 dev-system research (D-29)

## Context

`Session.luau` re-implemented a ProfileStore-style session lock without heartbeats, migrations or throttling handling. ProfileStore (MadStudioRoblox, Apache-2.0) is the maintained successor of ProfileService (whose README points new projects to it). "Do not reinvent the wheel."

## Options considered

| Option | Correctness of locking | Testability | Maintenance | Cost |
|---|---|---|---|---|
| A. Keep our `Session.luau` | Low-medium (no heartbeat or steal protocol) | High | Ours forever | Rewrites ProfileStore badly |
| B. ProfileStore vendored, behind our port | High (autosave, session steal, release on shutdown) | High with the in-memory fake and contract test | One vendored file, one maintainer, quiet since 2025-07 | Audit and bump |
| C. ProfileStore through Wally/pesde | High | High | Needs a package manager (ADR 0003) | Tooling migration |

## Decision

Option B. `vendor/ProfileStore/` holds an unmodified copy pinned to commit `45c9847cbcf1fc260369c50eb335aba7c35aecdd`, with its Apache-2.0 `LICENSE` and a README recording provenance and the review done (the whole file was read as data before vendoring). The port is `src/shared/ports/ProfileRepository.luau`; `ProfileStoreRepository` is the only adapter that knows ProfileStore. `InMemoryProfileRepository` is the test double; both must pass `tests/features/playerdata/ProfileRepository.contract.luau`. `Session.luau`, `RobloxDataStoreBackend.luau` and their tests are removed. The purchase ledger lives inside the profile (`PlayerData.purchases`).

## Consequences

- Positive: proven lock protocol; the game depends on a small typed port; the old module's behaviors became the port contract tests.
- Negative: a third-party file to keep current; control of the lock algorithm is lost; `Profile:Save()` is asynchronous so `save()` reports scheduling, not completion; only ProfileStore's `Mock` mode exists for Studio without API access; the new Luau solver does not accept ProfileStore's `T & JSONAcceptable` data type without a closure bridge in `Main.server`.

## What would change this decision

ProfileStore abandoned with an open data-loss bug, or a game needing sub-second multi-server writes (then use MemoryStore or Open Cloud for that data, not profiles). Schema migrations (D-30) are a separate pure module to add before the first schema change.
