# ADR 0013: Multi-agent protocol with a Studio lock

- Status: accepted by recommendation 2026-11-02, revisable
- Date: 2026-11-02
- Source: R1 dev-system research (D-34, D-35; extends D-21)

## Context

Several agents will edit the repo in parallel. Code, types, lint and Lune tests need no Studio. The built-in Studio MCP can address several Studio instances (`studio_id`, `list_roblox_studios`), but a 16 GB machine cannot afford many Studios, and binary place files cannot be merged.

## Options considered

1. No rules (agents share one checkout and Studio).
2. One worktree per agent, headless by default, a single Studio lock, human-owned places.
3. One Studio per agent with no cap.

## Decision

Option 2, written in `docs/multi-agent.md` and summarized in `CLAUDE.md`. One worktree and branch per agent; each agent owns one feature folder; the headless gate (format, lint, analyze, Lune, `rojo build`) must pass before asking for Studio; Studio work is serialized by `.studio.lock` (gitignored, at the main checkout root, with agent id, worktree, branch, start time and rojo port); at most 1 Studio per active worktree and 1 open at once until RAM is measured with two and recorded in a new ADR; at most 3 agents (D-21); a stale lock (over 2 hours) is escalated, never deleted by another agent; humans approve monetization and player-data changes.

## Consequences

- Positive: parallel work without merge conflicts on shared files; the scarce resource (Studio RAM) is explicit; visual tasks have a clear owner.
- Negative: visual tasks serialize; agents cannot see the world without the lock; the lock is advisory (a file, not an OS mutex), so it relies on agents following the protocol.

## What would change this decision

Roblox shipping per-agent session isolation in the built-in MCP or a headless render path; a measurement showing two Studios fit in RAM (raise the cap by a new ADR).
