# ADR 0021: LihFolk Vault V2.5.0 as the project-scoped Roblox knowledge router

- Status: accepted 2026-11-03 on Victor's request ("I want those vaults downloaded, installed, seen and working")
- Date: 2026-11-03
- Refs: issue #7, ADR 0018 (Studio MCP at user scope), vault decision 0016 (kit library on D:)

## Context

Agents writing Roblox code guess dated facts: limits, quotas, prices, policy and APIs renamed in 2025-2026. That is where generated games break (lost saves, double grants, throttled DataStores). The LihFolk Vault V2.5.0 is 1,436 notes written for agents, a Claude Code plugin (22 skills, 3 agents, 6 commands) and a PostToolUse checker that flags known Luau mistakes on every edit. License: notes, skills, hooks and tools are CC BY 4.0 (credit "LihFolk Vault V2"); the separate Asset Pack may be used in our own games, including paid ones, but not redistributed.

NFRs: **pinned** (no silent updates from a third-party repository), **scoped** (no context cost in non-Roblox sessions), **reviewed before it runs** (anything that executes on its own is read first), **works headless** (workers in worktrees get it without a prompt), **our conventions win** (the template's ports and features layout, per-game design tokens).

## Options considered

| NFR | A. Official install from GitHub (`/plugin marketplace add lihfolk-cy/v2-vault`) at user scope | B. Pinned local copy on D:, enabled at project scope (chosen) | C. No plugin; copy notes into our own docs |
|---|---|---|---|
| Pinned | no: follows the repository | yes: the read-only extraction of the v2.5.0 zip, sha256 recorded | yes |
| Scoped to Roblox repos | no: every session pays for 22 skill descriptions | yes | yes |
| Reviewed before it runs | only if re-read on every update | once per version, at intake | n/a |
| Headless workers | yes | yes, the settings travel with the repository | n/a |
| Upkeep | none | a new version goes through the kit intake | we maintain 1,300 notes |
| Machine-portable | yes | no: the path is `D:\Victor\Roblox\kits\...` | yes |

## Decision

Option B. `.claude/settings.json` declares the directory marketplace `lihfolk` and enables `lihfolk@lihfolk`, written by `claude plugin marketplace add --scope project` and `claude plugin install --scope project`.

Reviewed at intake (2026-11-03):

- `hooks/scripts/lihfolk-check.{sh,awk,ps1}`: read stdin, `rules.tsv` and the edited file, print findings. No network, no process launch, no file or registry writes. `-ExecutionPolicy Bypass` applies only to its own `.ps1`.
- `_tools/vault.py` (the router's search): standard library only, writes only `_tools/.cache/search.json`, the one writable folder in the read-only extraction.
- Skills, agents and commands: no instructions that touch tokens, settings, permissions or downloads.

How the template uses it:

- Look up dated facts and high-stakes topics (player data, receipts, remotes, monetization policy) through the `lihfolk` router before writing them. Cite the note titles in the PR.
- The template's architecture wins: LihFolk's drop-in systems are references, not replacements for our ports and features.
- Each game derives its own UI tokens (delivery bar §4). The LihFolk UI design system is a reference for technique only.
- The `quality-score` rubric (8.5/10 with hard gates) is available for assets; it does not replace CI.

## Consequences

Positive:

- Agents check 2025-2026 facts against notes labelled `Roblox docs` or `Measured` instead of guessing.
- Every Luau edit gets a second, free static check on top of Selene and Luau LSP.

Negative:

- The settings name a local path: a clone on another machine warns that the marketplace is missing until the kit is installed there.
- Two checkers can disagree with each other (LihFolk's rules and our Selene config); our CI stays the gate.
- Notes can go stale; a new LihFolk version means a new intake and a re-read of its hooks.

What would change it: LihFolk publishing signed releases with a changelog of hook changes (then option A becomes acceptable), or the checker producing noise that slows workers down (then disable the hook with `LIHFOLK_HOOK=off` and keep only the router).
