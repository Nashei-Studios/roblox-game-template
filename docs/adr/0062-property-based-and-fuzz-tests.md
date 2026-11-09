# 0062. Property-based and fuzz tests for the economy, receipts and remotes

- Status: accepted
- Date: 2026-11-09
- Deciders: Victor Ruiz
- Refs: #169, ADR 0005 (Lune tests), 0012 (remote validation), 0016 (confirmed save before PurchaseGranted), 0017 (coverage gate)

## Context

When the same author, human or AI, writes the code and its tests, both share the same blind spots: the test checks the cases the author imagined, and a green run proves only that. The template's money path has the highest cost of a blind spot: a coins grant, a receipt that must not pay twice, and remote arguments that a hostile client fully controls. A bug there loses Robux or lets a player mint coins.

Example tests exist for all of it (`ProductGrants.test`, `Validation.test`, `PurchaseRequests.test`). They did not catch that `Config.validate` accepted a product granting `1e300` coins while `ProductGrants` refuses to apply anything above 2^53: the player would have paid and received nothing, forever, because the receipt keeps returning "not processed".

## Options considered

| Option | Cost | Finds what the author did not imagine | Fits Lune and the Luau CLI coverage run |
|---|---|---|---|
| A. In-repo generator (`tests/property/Prop.luau`, about 330 lines, seed, shrinking) | one file to maintain | yes | yes, no Lune API, loads under both runners |
| B. External property-testing library | a dependency to vet | yes | none found for Lune (checked 2026-11-09); the Roblox ones target Jest in the engine |
| C. More example tests | cheap | no, same blind spot | yes |
| D. Mutation testing | a tool plus long runs | partly | no mature Luau tool |

## Decision

Option A, with two layers:

1. **Property-based** (`tests/property/`). `Prop.check(name, generator, property)` runs at least 200 cases (300 by default, extra cases stop after 2 seconds). Each case has its own seed, derived from the property name, so a run is reproducible. On a failure it shrinks the input (numbers toward zero, strings shorter, lists with fewer elements) and prints `seed=N`; `Prop.check(name, gen, prop, { seed = N })` replays exactly that case. Generators: integer in a range, number (NaN, +-inf, -0, 2^53, 1e300 over-represented), string (empty, unicode, emoji, control bytes, big), lists, pairs, any value (nil, tables, functions, threads).
2. **Fuzz of remotes** (`tests/fuzz/`). Every `Validation` function and every request handler that reads a remote argument gets nil, wrong types, NaN, +-inf, 1 MB strings, tables with metatables that raise on every access, cyclic and 5000-deep tables, plus 300 random values. Contract: nothing raises, the result is well formed, and a rejected value never reaches the dependency behind the handler.

Properties on the economy and receipts: the balance is never negative, NaN or above 2^53; a rejected grant leaves the data untouched; an amount out of range is rejected and `Config.validate` agrees with `ProductGrants` on which amounts are out of range; `integerInRange` accepts exactly the finite integers in range; a repeated `PurchaseId` is granted at most once (with random grant and save failures); a failed grant is never recorded; the order and repetition of receipts do not change the total.

Both run in `lune run scripts/test` and in the coverage run, so they gate every PR without a new job. Cost: about 1 second.

## Consequences

Positive:
- The first run found a real bug (see Regression below) that the example tests missed.
- A failure is reproducible from one number in the log.
- New validators and handlers get a ready pattern: add them to `tests/fuzz/RemoteFuzz.test.luau`.

Negative:
- Random inputs can fail on a CI run that passed locally only if the seeds change; they do not (seeds derive from the property name), so a new bug appears when the code or the property changes, not by chance. Widening the search means raising `cases`.
- Shrinking is greedy and simple: it may stop at a local minimum that is not the smallest input.
- 200 cases is a floor, not a proof.

What this does not cover:
- Anything that needs the engine: the real `MarketplaceService`, `DataStoreService`, Zap-generated remote layers (it validates the schema before our validators), session locking and save races. Those need a playtest or the Luau Execution API (ADR 0005).
- Concurrency and yielding: `confirmSaved` is a plain function here.
- Receipt ledger eviction: `newListLedger` drops the oldest ids past its capacity, so a receipt older than the window could be granted twice (ADR 0016 documents it). The properties use a capacity above the number of distinct ids.
- Order independence holds for valid grants that do not overflow; near 2^53 the order decides which grant is rejected, by design.
- Mutation of the tests themselves (whether the properties would catch a seeded bug) is not measured.

## Regression found

`Config.validate` accepted a developer product whose coins grant exceeded 2^53 (for example `1e300`), but `ProductGrants.apply` rejects it as `invalid_amount`. Fixed with `Config.MAX_GRANT_COINS` and a regression test; a property keeps both caps in agreement.

## What would change this decision

A maintained property-testing library for Lune or the Luau CLI, or running these properties in the engine through the Luau Execution API.
