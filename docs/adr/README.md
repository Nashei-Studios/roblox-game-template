# Architecture Decision Records

MADR format. One decision per file, numbered, immutable: a change is a new ADR that supersedes the old one.
All below are "accepted by recommendation 2026-11-02, revisable" (from the R0 research).

| ADR | Decision |
|---|---|
| [0001](0001-strict-luau-not-roblox-ts.md) | Strict Luau, not roblox-ts |
| [0002](0002-rojo-partially-managed.md) | Rojo partially managed |
| [0003](0003-no-package-manager-yet.md) | No package manager until the first dependency |
| [0004](0004-studio-mcp-builtin-only.md) | Built-in Studio MCP only |
| [0005](0005-tests-lune-then-luau-execution.md) | Lune for pure logic, Luau Execution API later |
| [0006](0006-assets-by-reference.md) | Assets by reference, no Git LFS |
| [0007](0007-luau-lsp-analyze-in-ci.md) | luau-lsp analyze in CI with vendored Roblox definitions |
| [0008](0008-stable-solver-gate.md) | CI gates on the stable solver, new solver non-blocking |
| [0009](0009-plain-modules-constructor-di.md) | Plain modules, constructor DI, one Script per side, feature folders |
| [0010](0010-profilestore-behind-profilerepository.md) | ProfileStore (vendored) behind a ProfileRepository port |
| [0011](0011-flags-port-experience-configs.md) | Flags port over Experience Configs with in-repo defaults |
| [0012](0012-remote-validation-and-rate-limit.md) | Remote validation and rate limiting; code-gen spike deferred |
| [0013](0013-multi-agent-protocol.md) | Multi-agent protocol: worktree per agent, headless first, Studio lock |

Also decided (no ADR needed): toolchain via Rokit in the default `~/.rokit`, kept on C: (toolchains stay on the SSD).
