# Contributing

1. Open or find an issue first. Every PR links one with `Closes #N`.
2. Branch from `main` (`feat/<name>`, `fix/<name>`, `chore/<name>`), one worktree per agent ([docs/multi-agent.md](docs/multi-agent.md)).
3. Run the local gate before pushing: `stylua --check .`, `selene .`, `pwsh scripts/analyze.ps1`, `lune run scripts/test`, `pwsh scripts/coverage.ps1`.
4. Open the PR as a draft while it is unfinished (drafts run no CI). Title in Conventional Commits, in English; the squash commit uses it.
5. One push per logical change: each CI run is billed against the account's monthly minutes.
6. A new decision gets a new ADR in `docs/adr/`; accepted ADRs are never edited.
