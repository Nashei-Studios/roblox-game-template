# ADR 0002: Rojo partially managed

- Status: accepted by recommendation 2026-11-02, revisable
- Date: 2026-11-02
- Source: R0 toolchain research (decisions-proposed.md, D-02)

## Context

Rojo can own everything (fully managed) or only scripts (partially managed). Official docs call the fully managed workflow incomplete and Team Create 'prone to issues'.

## Options considered

1. Partially managed: code in Git via Rojo; world, terrain and UI built in Studio.
2. Fully managed: everything in files (`rojo syncback`; maturity unverified).

## Decision

Partially managed. `default.project.json` maps only Shared, Server and Client; services use `$ignoreUnknownInstances: true` so Rojo never deletes Studio-owned content.

## Consequences

- Positive: documented workflow, safe merges, scripts are diffable.
- Negative: world, terrain and UI data are not diffable or reviewable in Git.

## What would change this decision

Rojo publishes a solid fully managed guide, or syncback proves reliable on the first game.
