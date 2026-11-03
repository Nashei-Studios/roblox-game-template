# ADR 0009: Plain modules with constructor injection, one Script per side, feature folders

- Status: accepted by recommendation 2026-11-02, revisable
- Date: 2026-11-02
- Source: R1 dev-system research (D-24)

## Context

The template needs a code shape that agents and humans can extend without a framework. Knit (archived 2024-07-31) and Roact (archived 2023-12-13) are out. The previous layout mixed pure modules and adapters at the top of `src/shared` and `src/server`, with no per-feature grouping and two engine-facing files wired by hand in a TODO.

## Options considered

| Option | Type safety | Testability | Maintenance risk | Cost |
|---|---|---|---|---|
| A. Plain ModuleScripts, constructor DI, ports and adapters | High (typed `Deps` tables) | High (fakes, Lune) | Low (no dependency) | A composition root to maintain |
| B. A framework (Knit-like service locator) | Medium (runtime lookup) | Medium | High (abandoned ecosystem) | Magic, global registry |
| C. Many Scripts, each self-wiring | Medium | Low (load order implicit) | Medium | Race conditions at boot |

## Decision

Option A. `Service.new(deps: Deps): Service` with a typed dependencies table. `Main.server` and `Main.client` are the only Scripts and the only place that calls adapters. Types of external services are **ports** in `src/shared/ports`; implementations are **adapters** in `src/server/adapters`. Code is grouped by capability in `features/<feature>/` (shared for pure logic, server for engine-bound services); tests mirror the layout. See `docs/architecture.md` for the diagrams and the folder rationale.

## Consequences

- Positive: explicit load order, every dependency visible in a signature, features testable under Lune with fakes, template stays genre-agnostic.
- Negative: boilerplate (a `Deps` type per service); local structural type aliases are duplicated because Lune-loadable modules cannot `require` siblings by instance path; ports in `shared` expose server contracts (types only) to the client folder.

## What would change this decision

A dependency-injection library for Luau with typed resolution and an active maintainer, or a game large enough that the composition root needs to be split into modules per feature (then split `Main`, keep one Script).
