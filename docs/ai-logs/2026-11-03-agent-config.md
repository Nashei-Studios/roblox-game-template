# 2026-11-03 - Multi-agent Claude Code setup

## Goal
Finish the agent configuration of the template: Studio MCP at user scope, `.claude/` with a lock-enforcing hook and a Luau reviewer.

## Decisions
- ADR 0018: delete the project `.mcp.json` (second proxy per session, and a `\r` escape bug in its path); bootstrap installs the launcher to `~/.local/bin` and registers it at user scope only when missing. Supersedes only the registration clause of ADR 0004.
- The Studio lock (ADR 0013) is now enforced for Claude Code by a PreToolUse hook. The decision is a pure `--!strict` module (`.claude/hooks/StudioLockPolicy.luau`) tested in the Lune suite; `studio-lock.luau` only does I/O.
- Hook contract checked against the Claude Code hooks docs (context7): stdin JSON has `tool_name` and `tool_input` (`tool_input.command` for Bash); exit 0 allows, exit 2 blocks and stderr goes to the model.
- `scripts/analyze.ps1` also analyzes `.claude/hooks`.

## Changes
`.claude/settings.json` (deny secrets, allow gate commands, hook on `mcp__Roblox_Studio__.*` and `Bash|PowerShell`), `.claude/agents/luau-reviewer.md` (read-only), ADR 0018, README, CLAUDE.md, docs/multi-agent.md, bootstrap step 5.

## Verification
stylua --check, selene, analyze, `lune run scripts/test` (110 passed), coverage 97.2 % (threshold 75), `rojo build`. Hook piped with a Studio call without lock: exit 2; a Read call: exit 0; `rojo serve` without lock: exit 2.

## Not done
- Bootstrap was not run and `~/.claude.json` was not touched (by instruction).
- The hook was not exercised inside a live Claude Code session, only with piped payloads. Settings `Read(...)` deny patterns follow the permission-rule syntax but were not tried against a real denied read.
- The hook needs `lune` and `git` on the PATH of the Claude Code process.
