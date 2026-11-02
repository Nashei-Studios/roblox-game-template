# ADR 0001: Strict Luau instead of roblox-ts

- Status: accepted by recommendation 2026-11-02, revisable
- Date: 2026-11-02
- Source: R0 toolchain research (decisions-proposed.md, D-01)

## Context

The game code needs one language. Roblox's native language is Luau; roblox-ts compiles TypeScript to Luau.

## Options considered

1. Strict Luau (`--!strict` in every script).
2. roblox-ts 3.0.0 (last release 2024-09; adds a compile step; many JS APIs do not exist).

## Decision

Strict Luau, enforced by `.luaurc` (`languageMode: strict`) and a `--!strict` header in every `.luau` file.

## Consequences

- Positive: native language, no compile step, less tooling, most Roblox docs are Luau; no evidence that roblox-ts helps LLM agents.
- Negative: no TypeScript refactoring tools or npm ecosystem.

## What would change this decision

The team becomes TypeScript-fluent and accepts the compile step, or evidence appears that roblox-ts improves agent output.
