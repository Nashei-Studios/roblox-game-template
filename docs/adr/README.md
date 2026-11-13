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
| [0040](0040-social-hub-scaffold.md) | Social hub scaffold: layout, slots and cap as data |
| [0041](0041-locomotion-and-tool-controller.md) | Locomotion and tool controller: the server owns the state |
| [0042](0042-clip-moment-over-capture-service.md) | Clip moment: a timed plan over CaptureService |
| [0043](0043-music-director-and-licence-manifest.md) | Music director with moment stings and a licence manifest |
| [0044](0044-win-condition-checklist-and-gate.md) | Win-condition checklist and a pending-tolerant gate |
| [0045](0045-ui-spacing-and-platform-aware-controls.md) | UI spacing and platform-aware controls are born from the ecosystem |
| [0046](0046-collection-index-mold.md) | CollectionIndex mold: server-side discovery through a port, silhouettes, a bar to finite milestones, claim or auto |
| [0047](0047-team-create-and-rojo-split.md) | Team Create for the world and art, Rojo for code; one Rojo host; reusable models as Packages |
| [0048](0048-item-icon-and-rarity-language.md) | ItemIcon and RarityFx: an image per item and one rarity language |
| [0049](0049-shared-objective-mold.md) | Shared objective mold: a server-authoritative goal the whole server pushes |
| [0050](0050-mood-resolver-over-signals.md) | Mood resolver: the music mood from game state through a signals port |
| [0051](0051-moment-settings-and-capture-routing.md) | Moment settings: opt-outs for effects, capture and share, and capture routing |
| [0052](0052-visible-coplay-hint.md) | Visible co-play hint: make the existing bonus visible, never pay it from the text |
| [0053](0053-presence-board-over-a-feed-store.md) | Presence board: what other players did, from a capped feed behind a port |
| [0054](0054-reveal-moment-over-the-clip-moment-director.md) | Reveal moment: a short skippable unlock beat on top of the clip moment director |
| [0055](0055-item-slots-mold.md) | Item slots mold: a hotbar of equipped items on the HUD bottom rail |
| [0056](0056-podium3d-world-leaderboard.md) | Podium3D: the top three of a board as avatar statues on a 3-step podium |
| [0057](0057-tier-model-set-mold.md) | TierModelSet mold: a distinct model, material and color set per tier |
| [0058](0058-auto-feel-profiles-and-scheduler.md) | AutoFeel mold: one hit-feel pipeline, two voices, and a pure scheduler for automatic mining |
| [0060](0060-inspect-view-mold.md) | InspectView mold: rotate and zoom one item in a ViewportFrame |
| [0061](0061-ui-gate-rules.md) | UI gate rules: duplicate destinations, scroll overlap, motion, button limits and touch locomotion |
| [0062](0062-property-based-and-fuzz-tests.md) | Property-based and fuzz tests for the economy, receipts and remotes (seeded, shrinking, in-repo generator) |
| [0064](0064-onboarding-experiments.md) | Onboarding experiments: deterministic server-side assignment (FNV-1a of UserId and experiment id), variant on funnel events, `session_5min` |
| [0065](0065-group-workflow-github-source-notion-view.md) | Group workflow: GitHub is the source of truth, Notion the view; Agent Board, one-way Notion mirror, HUD limit 4 touch and 6 keyboard |
| [0066](0066-branch-guard-without-server-rules.md) | Guard for main and develop where the server cannot enforce rules: pre-push hook, audit workflow, rulesets on public repos |
| [0068](0068-game-docs-scaffold-and-docs-check.md) | Game documentation scaffold in `docs/game/` (18 molds, stage gate) and the `docs-check` validator in Luau |
| [0069](0069-template-sync-to-games.md) | Template sync: `.templatesync` allow-list manifest, daily pull in each game, one reviewable PR with issue, no merge |

Also decided (no ADR needed): toolchain via Rokit in the default `~/.rokit`, kept on C: (toolchains stay on the SSD).
