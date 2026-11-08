# CLAUDE.md

Roblox game template. Strict Luau, Rojo (partially managed), Lune tests. Read `README.md` first.

## Structure
- `src/shared` -> ReplicatedStorage/Shared. Pure logic, loads under Lune: `ports/` (types), `features/<name>/`, `net/`.
- `src/server` -> ServerScriptService/Server. `Main.server` is the ONLY Script (composition root); `adapters/` implement ports over engine services; `features/<name>/` server-only services.
- `src/client` -> StarterPlayerScripts/Client. `Main.client` is the ONLY LocalScript.
- `vendor/` pinned third-party code (ProfileStore) with LICENSE; never edit it. `types/` is data for `analyze`.
- `tests/` mirrors `src`; `scripts/suites.luau` neutral test runner (entries `test.luau` for Lune, `test_luau.luau` for Luau); `docs/adr/` decisions; `docs/architecture.md` diagrams.

## Commands (run via Rokit tools)
- `stylua .` format, `stylua --check .` verify
- `selene .` lint
- `lune run scripts/test` unit tests (add new suites to the list in `scripts/suites.luau`)
- `lune run scripts/ui-audit` static UI audit over `assets/ui` (spacing, scrollers, text fit, 44 px, kit strokes); runtime half in docs/ui-audit.md
- `pwsh scripts/coverage.ps1` line coverage gate (75 % of the total, ADR 0017)
- `lune run scripts/perf-budget` worst-case remote bandwidth vs `src/shared/perf/PerfBudget` (ADR 0019); every new remote needs a rate entry there
- `lune run scripts/own-analytics [out] [days]` own-game Open Cloud analytics (CI only, needs ROBLOX_UNIVERSE_ID and ROBLOX_ANALYTICS_KEY; ADR 0023); never print or commit its values
- `pwsh scripts/generate-remotes.ps1` regenerate `src/shared/net/generated/` from `net/schema.zap` (never edit generated files)
- `pwsh scripts/analyze.ps1` type-check (`-NewSolver` for the informational pass)
- `rojo serve` sync to Studio

## Rules
- Every `.luau` file starts with `--!strict`. No `any`. Every exported function has typed params and return.
- Business logic goes in pure modules with constructor-injected `Deps`; engine calls stay in adapters that implement a port. Only `Main.*` builds adapters. No frameworks, no service locators.
- Player data only through `ProfileRepository`; remote arguments only through `net/Validation` and a `RateLimiter`.
- Errors are values (typed Result), never silently swallowed.
- Ids (game passes, products) stay `nil` with `-- TODO(victor): set id` until real. Never invent ids.
- New decision -> new ADR in `docs/adr/`, never edit an accepted one.
- Conventional Commits in English (`feat|fix|docs|style|refactor|perf|test|chore`); CI checks the PR title. Everything enters by PR with `Closes #N`, "how it was verified" and the ai-log link (`.github/pull_request_template.md`). No AI attribution in commits or PRs.
- Branches (ADR 0029): features and fixes go to `develop` by squash PR, and the branch is deleted. PRs into `develop` do not close issues, so close them by hand after the merge. A release is a PR `develop -> main` titled `chore(release): vX.Y.Z - <title>`, squash-merged (one commit per release on `main`), then an annotated tag, `gh release create --generate-notes` and a back-merge `git merge -s ours origin/main` into `develop`. `main` stays the default branch.
- Coverage gate 75 % (ADR 0017). Work leaves the machine at the first commit: push after every commit. Session with technical decisions -> `docs/ai-logs/YYYY-MM-DD-topic.md` (skill `ai-log`).
- CI is budget: one trigger per change, no CI on drafts or docs-only changes, `timeout-minutes` on every job, `concurrency` cancel-in-progress. Reproduce failures locally before pushing. Details: skill `github-integrado`.

## Roblox knowledge (ADR 0021)
- The `lihfolk` plugin is enabled at project scope from the pinned copy in `D:\Victor\Roblox\kits\lihfolk-vault-v2.5.0\`. Before writing player data, receipts, remotes, monetization or anything with a 2025-2026 limit, price or policy, look it up through the `lihfolk` router (or `python -I "<vault>/_tools/vault.py" "<question>"`) and cite the note titles in the PR.
- The template's ports and features layout wins over LihFolk's drop-in systems; each game derives its own UI tokens. LihFolk's checker findings are hints; our CI is the gate.

## Skill routing
Luau/Roblox rules: `~/.claude/rules/luau.md`. Structure, tests, CI: `arquitectura-por-stack` -> `tdd` -> `github-integrado`. Decision: `grilling` -> `adr`. Before a PR: `/review-pr`, `/check-coverage`, `security-audit` (before merging to `main` when remotes, purchases or player data changed). Text people read (README, PR): `humanizer`.

## Multi-agent (docs/multi-agent.md)
- One git worktree and branch per agent; own one `features/<name>/` folder; cross-feature, `ports/`, `Main.*`, `vendor/`, CI go through the orchestrator.
- Headless first: `stylua --check .`, `selene .`, `pwsh scripts/analyze.ps1`, `lune run scripts/test`, `rojo build` must pass before you ask for Studio.
- Studio only while holding `.studio.lock` (main checkout root, gitignored: agent, worktree, branch, start time, rojo port). Max 3 agents, 1 Studio open at a time. Always pass `studio_id`. Delete the lock when done; never delete another agent's lock, report stale ones (over 2 h).
- `.claude/` (settings, `hooks/studio-lock`, `agents/luau-reviewer`) enforces the lock for Claude Code: Studio MCP tools and `rojo serve` are blocked (exit 2) unless `.studio.lock` names this worktree. Run `luau-reviewer` on the diff before a PR.
- Never merge `.rbxl` files. Monetization and player-data changes need human approval.

## Assets and skills
- Third-party kits: `assets/kits.manifest.luau` (ADR 0027). Binaries stay in `D:/Victor/Roblox/kits`; copy into the git-ignored `assets/kits/<slug>` and use `"$path": "assets/kits/<slug>"`. Respect each kit's `license` and `ships`.
- Roblox skills live globally in `~/.claude/skills` (roblox-*, make-map, make-model, make-anim, quality-score, roblox-characters, roblox-physics and others) and load by description; nothing is copied into this repo.

## Forbidden
- Community MCP servers; only the Studio built-in MCP (`Roblox_Studio`), and only on a dev/throwaway place.
- Secrets, API keys or tokens in the repo (Open Cloud keys go in GitHub secrets).
- Anything that spends or moves real money; test purchases only on a dev place.
- Editing Studio-owned content through files (world, terrain, UI) or enabling fully managed Rojo without an ADR.
- Adding a package manager or dependency without an ADR.
