# ADR 0015: Remote layer code generator (Zap vs Blink)

- Status: accepted 2026-11-03: option A applied as the recommended, reversible default while Victor was away (his standing instruction: apply the recommended option); a superseding ADR switches to B or C
- Date: 2026-11-02
- Source: spike D-27 (`spikes/zap-vs-blink`, outside this repo), R1 dev-system Q3. Follows ADR 0012.

## Context

ADR 0012 fixed the security policy for remotes (intent only, `Validation`, `RateLimiter`) and deferred the choice of a
typed schema generator to a one-day spike on 5 events. The spike ran Zap 0.6.29 (`red-blox/zap`, MIT) and Blink 0.18.9
(`1Axen/blink`, MIT) on the same schema: `RequestPurchase` (client to server, enum), `CoinsChanged` (server to client,
u32), `PlayerStateSync` (server to client, struct with 6 fields and an array), `UseAbility` (client to server,
unreliable, vector + u8), `Emote` (client to server, unreliable, enum).

NFRs that matter here: strict typing under `luau-lsp analyze` on both solvers (ADR 0007, 0008), agent-friendly files
(plain-text schema, CLI generator), low maintenance risk, security stays ours (ADR 0012), no dependency without an ADR.

## Options considered

1. Zap 0.6.29.
2. Blink 0.18.9 (stable; `1.0.0-pre.10` exists and is not considered).
3. Hand-written RemoteEvents with shared `Types` and validators (the fallback from the R1 research; not spiked).

Measured on the spike (details and commands in the spike README):

| Axis | Zap | Blink |
|---|---|---|
| Analyze on generated files, both solvers | 0 errors, but header is `--!nocheck` (forced `--!strict`: 22 and 17 errors) | 0 errors, header is `--!strict` |
| Strict consumer, both solvers; 4 deliberate type bugs caught | 0 errors; 4 of 4 | 0 errors; 4 of 4 |
| Param names in the API | named from the schema | positional (`Value1`, `Value2`) |
| `vector` | Luau `vector` | `Vector3` |
| selene on output | 0 warnings | 58 warnings (needs an exclusion) |
| Size | 1069 lines, 34.0 KB | 1135 lines, 33.6 KB |
| Library validates on read | enums, ranges, array and string length, UTF-8 | enums, ranges, array and string length |
| Neither validates | NaN and infinity, authority, rate, cooldowns | same |
| Unreliable, buffers, batching | yes | yes |
| Editor | web playground, no VS Code extension found | Studio plugin, no VS Code extension found |
| Release / last commit | 2026-06-23 / 2026-06-23; rewrite branch under way, 0.6.x maintained separately | 2026-09-19 / 2026-09-19; v1 pre-releases in flight |
| Bus factor | two main contributors (133 and 98 of 331 commits) | one author, 205 of 232 commits (88 %) |
| Open issues | 9 | 19 (including #102: errors inside the receive loop) |
| Real bandwidth | not measured (needs Studio) | not measured |

## Decision

None yet. The measured evidence does not separate them: both pass `analyze` on both solvers, both are MIT, both give the
same typed API, both leave NaN, authority and rate to `Validation` and `RateLimiter`, and the only public bandwidth
benchmark (author-run, old versions, linked in the spike README) shows parity. What differs is risk appetite, which is
Victor's call.

Closed question for Victor:

- **A. Zap 0.6.29 (recommended).** Named params, native `vector`, UTF-8 check, clean selene, two active maintainers.
  Loses: the generated body is `--!nocheck` (we type the API through `typeof`, not the implementation), the release
  cadence slowed (last release 2026-06-23) and the project is mid-rewrite, so 0.6.x could become a dead end.
- **B. Blink 0.18.9.** Strict-checked output, newer releases, Studio plugin. Loses: positional params, `Vector3`
  instead of `vector`, 58 selene warnings to exclude, single maintainer, 1.0 pre-releases suggest breaking changes soon,
  an open issue about errors in the receive loop.
- **C. Neither yet:** keep the 0012 helpers with hand-written RemoteEvents until the first real game needs the bandwidth,
  and run a Studio bandwidth test then. Loses: typed schema and compression from day one.

## Consequences (of whichever is chosen)

- Positive: one schema file, generated typed API, buffers; the server edge still goes through `Validation` and `RateLimiter`.
- Negative: a third-party generator in the toolchain; a regeneration step that CI must verify (`git diff --exit-code`).
- Integration plan once decided: pin the CLI in `rokit.toml`; schema in `net/schema.<ext>`; generated code in
  `src/shared/net/generated/` with a "generated, do not edit" header and excluded from stylua and selene; `RequestPurchase`
  wired to `Validation` and `RateLimiter` in the server; a CI step that regenerates and fails on diff; a "how to add an
  event" section in `docs/architecture.md`. None of this is done in this branch.

## What would change this decision

Bandwidth measured in Studio favoring one clearly; Zap shipping its rewrite with a different schema, or going quiet for
another six months; Blink adding a second maintainer or reaching 1.0; either tool adding NaN checks, a rate limit or an
error policy for invalid input; Roblox shipping first-party typed remotes.
