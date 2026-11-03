# 2026-11-03: Zap as the typed remote layer (ADR 0015, option A)

## Goal
Integrate Zap 0.6.29 following the "Integration plan once decided" of ADR 0015.

## What was done
- ADR 0015 status changed to accepted (option A, applied as the recommended reversible default while Victor was away). Body untouched; index updated.
- `rokit add red-blox/zap@0.6.29`; Zap was already trusted on this machine, so no explicit `rokit trust` was needed. On a fresh machine CI/README mention `rokit trust red-blox/zap`.
- `net/schema.zap` with the real events only: `RequestPurchase` (client to server, reliable, enum) and `CoinsChanged` (server to client, u32).
- `scripts/generate-remotes.ps1` runs Zap, normalizes to LF and adds a "GENERATED FILE, DO NOT EDIT" header after Zap's `--!` directives. Output in `src/shared/net/generated/{server,client,types}.luau`, excluded from stylua (`.styluaignore`), selene (`selene.toml`) and the coverage gate (it already excluded any `generated` folder).
- `features/monetization/PurchaseRequests` (pure, injected `allow` and `prompt`): rate limiter first, then `Validation.oneOf`, then the prompt. Wired in `Main.server` only; limiter bucket released on PlayerRemoving. `Config.findProductByName` added for the id lookup.
- `Main.server` fires `CoinsChanged` after a successful grant; `Main.client` listens to it.
- CI job `remotes` regenerates and runs `git diff --exit-code`; architecture section "How to add a remote event"; README and CLAUDE.md updated.

## Decisions
- **Enum, not bounded string, for the product name.** Config is a static typed table edited in code, so its names can be mirrored in the schema (`enum { "Coins100" }`). The enum gives the library-level reject and a typed param; the handler still checks against Config names, so drift can only make a product unreachable, never unsafe. Cost: two places to edit when adding a product (documented in architecture.md). A bounded string would remove the drift but lose the typed enum and the early drop.
- **Rate limit before validation**: a flooded client costs one bucket lookup. Test asserts a garbage payload over budget reports `rate_limited`.
- **Header via script, not hand edit**: Zap has no option for a custom header, so the wrapper post-processes; CI runs the same script so the diff check covers it.
- **CoinsChanged clamps to u32 (4294967295)** in `Main.server`: `ProductGrants.MAX_COINS` is 2^53 and a larger balance would make the generated writer error. Small, safe clamp; revisit if coins can exceed 4.29e9.
- Rate budget (capacity 3, 0.5 per second) is a placeholder default in `Main.server`; no measured basis.

## Verification
`stylua --check .` exit 0; `selene .` 0 errors, 0 warnings; `analyze` exit 0 (a deliberate `string = coins` in the client was caught: TypeError, so the consumer API is typed); `lune run scripts/test` 116 passed, 0 failed; coverage 97.3 % (548/563 lines); `rojo build` ok; regenerate + `git diff --exit-code` exit 0. Logs in `logs/*-zap.log` (gitignored).

## Open items
- Studio verification of the remotes (real RemoteEvents created by Zap, `PromptProductPurchase`) is not done: no Studio session. Product ids stay `nil`, so the prompt returns false until Victor sets them.
- The generated body is `--!nocheck` (ADR 0015); only the consumer API is typed.
- CI not run (no remote). The `remotes` job assumes `pwsh` on ubuntu-latest and `zap` resolved by Rokit from `rokit.toml`.
- Bandwidth not measured (needs Studio).
