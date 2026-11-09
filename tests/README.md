# tests

Pure-logic tests, run by `lune run scripts/test` (and by the Luau CLI for coverage, see ADR 0017). The harness is `harness.luau`; every test file is registered in `scripts/suites.luau`.

## Layout

| Folder | What it holds |
|---|---|
| `features/`, `net/`, `adapters/`, `claude/` | Example tests that mirror `src/` |
| `property/` | Property-based tests (ADR 0062): the generator `Prop.luau`, its own tests, and invariants over the economy and receipts |
| `fuzz/` | Fuzz of every remote validator and request handler (ADR 0062) |
| `fixtures/`, `assets/`, `perf/`, `ops/`, `scripts/` | Data and checks for other gates |

## Adversarial tests (ADR 0062)

The author of the code and of its tests shares the same blind spots, so these try to break the code.

- `Prop.check(name, generator, property, options?)` runs at least 200 generated cases, bounded in time. A failing property prints `seed=N` and the shrunk input.
- Replay a failure: `Prop.check(name, generator, property, { seed = N })`.
- Generators: `Prop.integer(low, high)`, `Prop.number()` (NaN, +-inf, 2^53, huge), `Prop.string()` (empty, unicode, emoji, big), `Prop.listOf(gen, max)`, `Prop.pair(a, b)`, `Prop.anything()` (nil, tables, functions, threads), `Prop.make(generate, shrink)` for your own.
- Add a new remote handler to the fuzz: add a test to `fuzz/RemoteFuzz.test.luau` that calls it through `fuzz(name, call, observe)`.
- A property that finds a bug is fixed in the same change, with a deterministic regression test next to it.

Run only these: they are part of `lune run scripts/test`; there is no separate command.
