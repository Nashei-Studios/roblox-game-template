# 0039. Adopt the global gitflow: develop default, automatic merges, automated releases

- Status: accepted
- Date: 2026-11-08
- Deciders: Victor Ruiz
- Supersedes in part: 0029 (default branch, release merge method, back-merge)

## Context

Victor made one release flow global for every project of the factory (full decision and comparison: ADR 0025 in `vruizz22/claude-code-global`, `docs/adr/`). This template is what each game inherits when it is stamped, so it carries the workflows.

## Decision

- `develop` is the default branch and receives squash PRs. `Closes #N` therefore closes issues by itself.
- `main` is production and receives only releases: PR `develop -> main` with a **merge commit**, so no back-merge is needed.
- Tool: git-cliff (`cliff.toml`) computes the next 0.x version and the CHANGELOG from Conventional Commits; `release.yml` does the PR, tag and GitHub Release. Trigger: `gh workflow run release.yml`, plus a weekly floor on Monday.
- `ci.yml` gains a `changes` job (docs-only PRs skip the toolchain but can still merge), `workflow_call` (the release reuses it as its gate) and an `automerge` job.
- Draft means blocked: a PR that changes the game runtime stays draft until it is verified in Studio; marking it ready lets it merge when green.
- `stale.yml` closes idle or conflicting non-draft PRs; `dependabot-automerge.yml` merges minor and patch updates.
- Both automerge paths are off until the repo variable `AUTOMERGE_ENABLED` is `true`.
- `github-integrado` in `~/.claude` has the one-command setup (`plant-gitflow.ps1`) that applies repo settings and copies these files.

## Consequences

- Positive: no PR waits for a human to press merge; releases are one command; the CHANGELOG cannot drift.
- Negative: without branch protection (GitHub Free) the gate is enforced by the workflow, not by GitHub; a person can still push to `main`. Publishing the place and going public stay manual (ADR 0002 and Victor's milestones).
- Each stamped game owns a copy of the workflows; drift is fixed by re-running `plant-gitflow.ps1`.
