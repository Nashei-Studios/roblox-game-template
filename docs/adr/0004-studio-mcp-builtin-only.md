# ADR 0004: Built-in Studio MCP only

- Status: accepted by recommendation 2026-11-02, revisable
- Date: 2026-11-02
- Source: R0 toolchain research (decisions-proposed.md, D-05)

## Context

The official MCP server is built into Studio (stdio, `%LOCALAPPDATA%\Roblox\mcp.bat`). It can read and modify open places, and `execute_luau` runs arbitrary Luau. The standalone Rust server is archived. Community servers are untrusted code.

## Options considered

1. Built-in server only, project-scoped, dev/throwaway place first, Git for rollback.
2. A community server (more features, supply-chain risk).
3. The archived standalone binary.

## Decision

Option 1. Registered in `.mcp.json` (name `Roblox_Studio`). Policy: dev place only, no production place connected, rollback through Git.

## Consequences

- Positive: official, no extra supply chain.
- Negative: fewer extra features; the `.mcp.json` command is derived from docs and must be verified after Studio installs.

## What would change this decision

The built-in server proves insufficient and a community server's code is read and audited.
