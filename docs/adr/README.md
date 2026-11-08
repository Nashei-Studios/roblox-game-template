# Architecture Decision Records

MADR format. One decision per file, numbered, immutable: a change is a new ADR that supersedes the old one.
All below are "accepted by recommendation 2026-11-02, revisable" (from the R0 research).

| ADR | Decision |
|---|---|
| [0001](0001-strict-luau-not-roblox-ts.md) | Strict Luau, not roblox-ts |
| [0002](0002-rojo-partially-managed.md) | Rojo partially managed |
| [0003](0003-no-package-manager-yet.md) | No package manager until the first dependency (superseded by 0028) |
| [0004](0004-studio-mcp-builtin-only.md) | Built-in Studio MCP only (registration superseded in part by 0018) |
| [0005](0005-tests-lune-then-luau-execution.md) | Lune for pure logic, Luau Execution API later |
| [0006](0006-assets-by-reference.md) | Assets by reference, no Git LFS |
| [0007](0007-luau-lsp-analyze-in-ci.md) | luau-lsp analyze in CI with vendored Roblox definitions |
| [0008](0008-stable-solver-gate.md) | CI gates on the stable solver, new solver non-blocking |
| [0009](0009-plain-modules-constructor-di.md) | Plain modules, constructor DI, one Script per side, feature folders |
| [0010](0010-profilestore-behind-profilerepository.md) | ProfileStore (vendored) behind a ProfileRepository port |
| [0011](0011-flags-port-experience-configs.md) | Flags port over Experience Configs with in-repo defaults |
| [0012](0012-remote-validation-and-rate-limit.md) | Remote validation and rate limiting; code-gen spike deferred |
| [0013](0013-multi-agent-protocol.md) | Multi-agent protocol: worktree per agent, headless first, Studio lock |
| [0014](0014-pure-migration-chain.md) | Pure per-version migration chain for player data (golden fixtures) |
| [0015](0015-remote-layer-codegen.md) | Remote layer code generator, Zap vs Blink (accepted: Zap 0.6.29, option A) |
| [0016](0016-confirmed-save-before-purchase-granted.md) | PurchaseGranted only after the save is confirmed; bounded ordered ledger |
| [0017](0017-luau-coverage-gate.md) | Line-coverage gate with the Luau CLI (75 % of the total) |
| [0018](0018-studio-mcp-user-scope.md) | Studio MCP registered at user scope only (supersedes the registration clause of 0004) |
| [0019](0019-performance-budget.md) | Performance budget: static remote-bandwidth calculator plus a dev probe |
| 0020 | Reserved: each game branch (`game/*`) records its own game-specific 0020, so template ADRs skip it to avoid collisions when those branches merge `main` |
| [0021](0021-lihfolk-knowledge-plugin.md) | LihFolk Vault V2.5.0 as the project-scoped Roblox knowledge router (pinned local copy) |
| [0022](0022-game-systems-modules.md) | Game systems as config-driven feature modules behind ports |
| [0023](0023-own-game-analytics-in-ci.md) | Own-game analytics through Open Cloud in CI, private artifact output |
| [0024](0024-plus-prompt-robux-transfers-and-runtime-prices.md) | Roblox Plus sign-up prompt, Robux transfers and prices read at runtime |
| [0025](0025-engagement-modules.md) | Engagement modules: promo codes, time rewards, notifications, sound (implements 0022) |
| [0026](0026-ui-kit-leaderboards-community-reward.md) | UI kit, leaderboards and community join reward (implements 0022) |
| [0027](0027-kit-asset-manifest.md) | Kit asset manifest, binaries stay in the kit library (refines 0006) |
| [0028](0028-external-building-blocks-and-wally.md) | External building blocks first, Wally for registry packages, vendoring for the rest (supersedes 0003) |
| [0029](0029-develop-and-main-with-one-ci-run-per-change.md) | develop and main, one CI run per change |
| [0030](0030-social-layer-friend-boost-and-invite.md) | Social layer: friend boost and invite reward as a configurable perk |
| [0031](0031-invite-ledger-memorystore-and-friend-checks.md) | Invite ledger on MemoryStore and parallel friend checks |
| [0032](0032-join-architecture-data-as-background-state.md) | Join architecture: data is background state |
| [0033](0033-tap-anywhere-input-router.md) | Tap anywhere: a pure input router with blockers |
| [0034](0034-visible-progression-modules.md) | Visible progression modules: rules, announcer, hit effects, extra board stats, card grid |
| [0035](0035-ui-system-imperative-builders-over-kit-trees.md) | UI system: imperative builders over kit Instance trees, rules in pure modules |
| [0039](0039-global-gitflow-automation.md) | Adopt the global gitflow: develop default, automatic merges, automated releases |

Also decided (no ADR needed): toolchain via Rokit in the default `~/.rokit`, kept on C: (toolchains stay on the SSD).
