## What changed

<!-- One short paragraph. Link the decision (ADR) if there is one. -->

## How it was verified

- [ ] `stylua --check .`
- [ ] `selene .`
- [ ] `pwsh scripts/analyze.ps1`
- [ ] `lune run scripts/test`
- [ ] `pwsh scripts/coverage.ps1` (75 % gate)
- [ ] `lune run scripts/ui-audit` (static UI audit, 0 findings)
- [ ] Runtime UI audit when the UI changed (docs/ui-audit.md), or the findings listed:
- [ ] Not run here (say which and why):

## Links

Closes #
AI log: docs/ai-logs/

## Checklist

- [ ] PR title is a Conventional Commit in English (the squash commit uses it)
- [ ] No secrets, ids or prices invented (`-- TODO(victor)` stays)
- [ ] Monetization or player-data change: human approval noted
- [ ] Workflow change: jobs count, `timeout-minutes`, docs-only and draft behavior noted
