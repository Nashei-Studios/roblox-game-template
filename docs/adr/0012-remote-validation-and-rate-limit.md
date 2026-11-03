# ADR 0012: Server-side remote validation and per-player rate limiting; code-gen choice deferred to a spike

- Status: accepted by recommendation 2026-11-02, revisable
- Date: 2026-11-02
- Source: R1 dev-system research (D-28, D-27)

## Context

Everything a client sends through a RemoteEvent or RemoteFunction is untrusted: wrong types, NaN or infinity (both survive serialization), out-of-range numbers, huge strings, and floods. A typed schema generator (Zap or Blink) types the payload but does not decide authority or rate.

## Options considered

1. Trust the generated schema only.
2. Validate and rate-limit by hand inside each handler.
3. Shared pure helpers: `Validation` (typed validators over `unknown`) and `RateLimiter` (per-player token bucket with an injected clock), used by every handler.

## Decision

Option 3. Remotes carry **intent only** ("buy item X"); the server re-derives prices, ownership and state. `src/shared/net/Validation.luau` returns a typed `Result` per argument (`number` rejects NaN and infinity, `integerInRange`, `string` with length bounds, `oneOf` as an allow-list, `boolean`). `src/shared/net/RateLimiter.luau` is a token bucket per `userId` (burst `capacity`, sustained `refillPerSecond`, optional `cost`, `forget` on PlayerRemoving, a backwards clock never mints tokens). Both are pure and tested under Lune. They are not wired to any remote yet because the template defines none.

**D-27 (Zap vs Blink) is not decided here.** It stays a documented spike in `docs/milestones.md` to run before the first remote exists; its result becomes its own ADR. Generated code must pass `luau-lsp analyze` on both solvers.

## Consequences

- Positive: one place to audit remote security; handlers cannot use an argument they did not validate; limits are testable without the engine.
- Negative: handlers must call the helpers (a convention, enforced by review, not by the compiler); the bucket table holds one entry per active player.

## What would change this decision

The chosen code generator shipping built-in validation and rate limiting that covers these cases, or Roblox providing a first-party remote rate limit.
