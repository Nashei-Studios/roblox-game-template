# ADR 0003: No package manager until the first dependency

- Status: accepted by recommendation 2026-11-02, revisable
- Date: 2026-11-02
- Source: R0 toolchain research (decisions-proposed.md, D-04)

## Context

Wally has stale releases (0.3.2, 2023); pesde is active but has a smaller ecosystem. The template has no third-party dependency.

## Options considered

1. None for now.
2. Wally.
3. pesde.

## Decision

No package manager. The first real dependency triggers a new ADR that picks one.

## Consequences

- Positive: zero supply-chain surface, less setup.
- Negative: first dependency requires a tooling migration.

## What would change this decision

A dependency is needed that is not worth rewriting (for example a UI or networking library).
