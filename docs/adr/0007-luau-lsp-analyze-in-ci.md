# ADR 0007: luau-lsp analyze in CI with vendored Roblox definitions

- Status: accepted by recommendation 2026-11-02, revisable
- Date: 2026-11-02
- Source: R1 dev-system research (D-22)

## Context

The template pins `--!strict` but CI only ran StyLua, Selene and Lune. Selene lints; it does not type-check. Running `luau-lsp analyze` locally found a real type error in `tests/harness.luau:48` (`pcall` of a `() -> ()` is typed as returning one value, so `local ok, message = pcall(fn)` fails). `analyze` does not download Roblox definitions, so without them every engine global is "unknown".

## Options considered

1. No type-check in CI (status quo).
2. `luau-lsp analyze` with definitions downloaded at CI time.
3. `luau-lsp analyze` with the definitions file vendored in `types/` and pinned to the luau-lsp version.

## Decision

Option 3. `types/globalTypes.None.d.luau` (luau-lsp tag 1.70.1, MIT) is stored as data; source URL, commit and date are recorded in `types/README.md`. CI generates a sourcemap with `rojo sourcemap`, runs `lune setup` so `@lune/*` requires resolve (the `lune` alias in `.luaurc` points to `~/.lune/.typedefs/0.11.1/`), and runs analyze over `src`, `tests` and `scripts`. `scripts/analyze.ps1` does the same locally. The `harness.luau` error is fixed with a typed `guardedCall` wrapper around `xpcall`.

## Consequences

- Positive: strict typing is enforced by a gate, not by convention; the error that existed is fixed; reproducible (no network fetch of definitions in CI).
- Negative: a 670 KB data file in the repo; it must be bumped together with `luau-lsp` in `rokit.toml`; the `.luaurc` alias depends on the Lune version directory name.

## What would change this decision

luau-lsp shipping definitions inside the binary for `analyze`, or the file growing enough to justify fetching it in CI with a checksum.
