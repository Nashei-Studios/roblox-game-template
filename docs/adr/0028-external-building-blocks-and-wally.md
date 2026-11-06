# ADR 0028: External building blocks first, Wally for the packages that live there

- Status: accepted by recommendation 2026-11-06, revisable
- Date: 2026-11-06
- Supersedes: [0003](0003-no-package-manager-yet.md)
- Source: owner directive 2026-11-06 ("hacerlo ocupando open source o todo lo que hayamos encontrado, la idea no es rehacer todo desde cero"); vault notes `research/ecosistema-base-paridad-essentials` and `research/essentials-replacements-2026`

## Context

ADR 0003 said: no package manager until the first real dependency. The base ecosystem plan now has about twenty systems (see `docs/ecosystem-map.md`). Most of them have a Roblox native service or Open Cloud API behind them, and a few have a maintained open-source piece. Writing everything from scratch repeats work and adds code that nobody else maintains.

Two facts decide the matter, both checked on 2026-11-06:

- Wally is the only registry with the utilities we want (`sleitnick/trove` 1.8.0, `sleitnick/signal` 2.0.3), but its latest stable tool release is `v0.3.2` from 2023-06-05; `v0.4.0-alpha.1` came out on 2026-10-12. License of the tool: MPL-2.0 (the tool is not shipped inside a game).
- Several pieces we want are not on Wally under their official scope. A search of the Wally registry returned only forks for `Cmdr`, and no `centau` scope for `vide`. Cmdr's official releases are on GitHub (`v1.13.1`, 2026-09-30).

## Options considered

| Option | For | Against |
|---|---|---|
| A. Wally for registry packages, vendoring (pinned release plus commit SHA) for the rest | Largest registry; the two utilities we need are there; vendoring already works for ProfileStore | Tool is on an alpha line for new work and stable 0.3.2 is old; two mechanisms to explain |
| B. pesde | Active (`v0.7.4+registry.0.2.3`, 2026-09-09, MIT); lockfile and scripts | Smaller registry; `sleitnick` packages are not confirmed there; one more tool in Rokit for little gain today |
| C. Vendor everything, no package manager | Zero supply-chain surface, nothing new in the toolchain | Manual updates for every library; license and version tracking by hand grows with each piece |

## Decision

Option A.

1. **Policy "external first, glue second".** For every system in the base ecosystem the order is: (1) Roblox native service or Open Cloud API; (2) maintained open-source library with a license compatible with private commercial games; (3) Creator Store plugin or asset (read before use); (4) code we write. We write only the glue: the port, the adapter, validation, config and tests. If nothing external exists, the issue says so and names the MIT repository whose patterns we read.
2. **Wally** (installed through Rokit, pinned version) for packages published under their official scope. Initial list, none installed by this ADR: `sleitnick/trove` and `sleitnick/signal` (from `Sleitnick/RbxUtil`, MIT, pushed 2026-08-11). Version pinned in `wally.toml`; `Wally.lock` committed.
3. **Vendoring** under `vendor/<name>/` for anything not on Wally under its official scope (already: ProfileStore; next: Cmdr when the admin issue starts). Each vendored copy keeps its license file and a README entry with release tag, commit SHA and date read.
4. **Every package is read before it enters.** The pull request that adds it records what was read, the license, and the pushed date. No `loadstring`, no `require` by asset id, no network calls in a dependency.
5. This ADR creates no `wally.toml` and installs nothing. The first issue that needs a package adds the files in its own pull request.

Initial candidate list (checked with `gh repo view` on 2026-11-06):

| Piece | License | Last push | Use |
|---|---|---|---|
| MadStudioRoblox/ProfileStore | Apache-2.0 | 2025-07-31 | Persistence, already vendored |
| red-blox/zap | MIT | 2026-06-23 | Remotes codegen, already adopted |
| Sleitnick/RbxUtil (`trove`, `signal`) | MIT | 2026-08-11 | Cleanup and events, on Wally |
| evaera/Cmdr | MIT | 2026-10-21 | Dev console, vendored |
| centau/vide | MIT | 2026-10-26 | UI state, only when two games duplicate binding code |
| UpliftGames/wally | MPL-2.0 | 2026-10-12 | Package manager tool |
| pesde-pkg/pesde | MIT | 2026-10-31 | Fallback manager |

## Consequences

- Positive: less code to maintain; each system points at the piece that already solves it; the map shows what is ours.
- Positive: ProfileStore keeps working as-is; no migration.
- Negative: a supply-chain surface appears (registry packages and vendored code). Mitigation: pinned versions, read-before-add, lockfile.
- Negative: Wally's stable release is old; if the alpha line stalls we depend on a tool with little upkeep. Packages are plain source, so leaving is cheap.
- Negative: two mechanisms (Wally and vendoring) need documenting in the repository README when the first package lands.

## What would change this decision

- Wally stops publishing or breaks on a current Rokit/Rojo: switch to pesde (option B) for the same packages.
- Registry packages we need only exist on pesde: add pesde for those, or vendor.
- A dependency fails the read-before-add review or changes license: vendor a pinned older release or drop it.
