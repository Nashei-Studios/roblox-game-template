# ADR 0006: Assets by reference, no Git LFS

- Status: accepted by recommendation 2026-11-02, revisable
- Date: 2026-11-02
- Source: R0 toolchain research (decisions-proposed.md, D-07)

## Context

Binary assets (meshes, images, audio) bloat Git. Roblox hosts uploaded assets and refers to them by id. Real sizes are not measured yet.

## Options considered

1. Asset ids only in code or config.
2. Git LFS for `.rbxm` and images.

## Decision

References only. `.rbxm`, `.rbxl` and `.rbxlx` are git-ignored.

## Consequences

- Positive: small repo, no LFS quota on the free plan.
- Negative: source art is not versioned here; keep it in the art tool or a separate store.

## What would change this decision

Measured asset sizes show a real need for versioned binaries.
