# Architecture Decision Records

MADR format. One decision per file, numbered, immutable: a change is a new ADR that supersedes the old one.
All six below are "accepted by recommendation 2026-11-02, revisable" (from the R0 research).

| ADR | Decision |
|---|---|
| [0001](0001-strict-luau-not-roblox-ts.md) | Strict Luau, not roblox-ts |
| [0002](0002-rojo-partially-managed.md) | Rojo partially managed |
| [0003](0003-no-package-manager-yet.md) | No package manager until the first dependency |
| [0004](0004-studio-mcp-builtin-only.md) | Built-in Studio MCP only |
| [0005](0005-tests-lune-then-luau-execution.md) | Lune for pure logic, Luau Execution API later |
| [0006](0006-assets-by-reference.md) | Assets by reference, no Git LFS |

Also decided (no ADR needed): toolchain via Rokit in the default `~/.rokit`, kept on C: (toolchains stay on the SSD).
