# Multi-agent protocol

How several coding agents (and humans) work on this repo at once without stepping on each other. Decisions: [ADR 0013](adr/0013-multi-agent-protocol.md). Short imperative version: `CLAUDE.md`.

## Rules

1. **One git worktree and one branch per agent.** Never work in another agent's worktree or in the main checkout. Create it with `git worktree add ../<repo>-<agent-id> -b <type>/<topic>`. Remove it after the PR is merged.
2. **Each agent owns one `features/<name>/` folder** (plus its tests). Changes that cross features, touch `ports/`, `Main.*`, `vendor/`, `types/`, CI or ADR numbering go through the orchestrator.
3. **Headless first.** Before asking for Studio, an agent must pass, in its worktree: `stylua --check .`, `selene .`, `pwsh scripts/analyze.ps1`, `lune run scripts/test`, `rojo build default.project.json -o places/dev.rbxl`. Most work (logic, schemas, rate limiter, adapters' pure parts) never needs Studio.
4. **Studio is a shared, scarce resource** (see the lock below).
5. **Place files are never merged.** Each `.rbxl` has one human owner; world, terrain and UI edits happen in the owner's Studio. Agents never edit Studio-owned content through files.
6. **No credentials for agents.** Publishing and Open Cloud keys stay with Victor and the CI secret scope (key limited to the test place, Luau Execution only).

## Limits (D-21, D-35)

| Resource | Cap |
|---|---|
| Agents working at once (16 GB machine) | 3 |
| MCP servers per agent session | 4 |
| Studio instances per active worktree | 1 |
| Studio instances open at once, whole repo | 1, until someone measures RAM with two Studios and records the result in a new ADR |
| Humans in separate worktrees | up to 3; Team Create only for world content |

## Task split

| Task | Needs Studio | Where it runs |
|---|---|---|
| Pure logic, schemas, migrations, rate limiter | No | Any agent, Lune |
| Types, lint, format | No | Any agent |
| Adapters over DataStore, Marketplace, ConfigService | Engine behavior | Luau Execution API test place (headless, when wired); Studio only to debug |
| UI layout, world, terrain | Yes | Human in Studio |
| Playtest, console check, screenshot | Yes | One agent at a time, under the lock |
| Publishing | Yes + credentials | Victor only |

## Studio lock

Only the lock holder may drive Studio through the built-in MCP (`Roblox_Studio`) or run `rojo serve`.

The lock file is `.studio.lock` at the root of the **main checkout** (all worktrees share one repository; find it with `git rev-parse --git-common-dir`, whose parent directory is the main checkout). It is gitignored. Format, one `key=value` per line:

```
agent=<agent id>
worktree=<absolute path of the holder's worktree>
branch=<holder's branch>
started=<UTC ISO 8601, e.g. 2026-11-02T18:30:00Z>
port=<rojo serve port the holder uses>
```

```mermaid
sequenceDiagram
  participant A as Agent
  participant L as .studio.lock
  participant S as Studio + MCP
  A->>A: headless gate passes (stylua, selene, analyze, lune, rojo build)
  A->>L: create exclusively (fails if it exists)
  alt created
    A->>S: rojo serve on own port, list_roblox_studios, drive MCP with explicit studio_id
    A->>L: delete when done (also on failure)
  else exists
    A->>A: read holder and started; keep working headless, retry later
  end
```

Procedure:

1. **Acquire.** Create the file only if it does not exist. PowerShell: `New-Item -ItemType File -Path $lock -ErrorAction Stop` (it fails when the file exists), then write the five keys. Git Bash: `set -o noclobber; : > "$lock"`. If creation fails, you do not hold the lock.
2. **Work.** Serve your worktree on a non-default port (`rojo serve --port <n>`), connect Studio to it, call `list_roblox_studios`, and pass the explicit `studio_id` on every MCP call. Use a dev or throwaway place only (ADR 0004).
3. **Release.** Delete the file as soon as the Studio task ends, including when it fails. Close the Studio you opened.
4. **Stale locks.** A lock older than 2 hours is suspect, not free. Do not delete it: report the holder, worktree and `started` to the orchestrator, who decides. Only the orchestrator or Victor removes another agent's lock.
5. **Acceptance per step.** Acquire: the file exists and shows your agent id. Work: `list_roblox_studios` lists exactly the Studio you opened. Release: the file is gone and `git status` in the main checkout shows nothing new.

If a step fails, stop and report; do not retry in a loop and do not bypass the lock.

## Review gates

A PR from an agent merges only when all hold:

1. CI is green: format, lint, analyze (stable solver), tests, `rojo build` smoke. The new-solver job is informational.
2. A reviewer equivalent to `dds-reviewer` (design, SOLID, pattern abuse) and `type-auditor` (no `any`, typed exports) has been run on the diff, with findings fixed or recorded.
3. A **human approves** anything that touches monetization (`ProcessReceipt`, ledger, grants) or player data (profile schema, `PlayerData`, `ProfileRepository`).
4. The PR links its issue, states what changed and how it was verified, and adds an ADR when it makes an architectural decision.
