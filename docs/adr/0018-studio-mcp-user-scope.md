# ADR 0018: Studio MCP registered at user scope only

- Status: accepted 2026-11-03, revisable
- Date: 2026-11-03
- Supersedes: the registration clause of [ADR 0004](0004-studio-mcp-builtin-only.md) ("Registered in `.mcp.json`"). The rest of ADR 0004 (built-in server only, dev place only, rollback through Git) stays in force.

## Context

ADR 0004 registered the built-in Studio MCP proxy per project in `.mcp.json`. Two problems showed up:

1. The machine-wide rule is that MCP servers are registered only at user scope (`~/.claude.json`), where `Roblox_Studio` already points to `cmd.exe /c C:\Users\Victor\.local\bin\roblox-studio-mcp.cmd`. A project copy makes every session in this repo start a second `StudioMCP.exe` proxy, and with several agents in worktrees (ADR 0013) that multiplies proxies against a Studio that should be driven by one lock holder.
2. The file had an escaping bug: in JSON, `"tools\roblox-studio-mcp.cmd"` turns `\r` into a carriage return, so the path was broken.

Access control for Studio is the lock in ADR 0013, enforced for Claude Code agents by `.claude/hooks/studio-lock`; that hook matches tool names, not where the server was registered, so it works the same at user scope.

## Options considered

1. Keep `.mcp.json` per project and fix the escaping (`tools/roblox-studio-mcp.cmd`).
2. Register only at user scope; the repo keeps the launcher as an install source and `scripts/bootstrap.ps1` copies it to `~/.local/bin` and registers it when missing.
3. Document the manual `claude mcp add` command and do nothing in bootstrap.

## Decision

Option 2. `.mcp.json` is deleted. `tools/roblox-studio-mcp.cmd` stays as the versioned source of the launcher. Bootstrap step 5 copies it to `$HOME\.local\bin` when missing or different (hash), then runs `claude mcp add --scope user Roblox_Studio -- cmd.exe /c <launcher>` only when `claude mcp get Roblox_Studio` fails, and prints what it did.

## Consequences

- Positive: one proxy per session regardless of repo; no duplicated registration; one place to change the launcher path; the escaping bug disappears with the file.
- Positive: a fresh machine still gets the setup from one command.
- Negative: the registration is no longer versioned with the repo; a clone on a machine where bootstrap was not run has no `Roblox_Studio` until it is.
- Negative: the installed launcher can drift from `tools/`; bootstrap re-copies it when the hash differs, but only when it is re-run.

## What would change this decision

Claude Code gaining per-project server deduplication, or the team needing a pinned per-repo server version.
