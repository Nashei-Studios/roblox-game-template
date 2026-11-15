# 2026-11-15 Load budget page and private load test checklist

- Scope: issues #202 and #203, branch `docs/load-budget-qa-202-203`. Two documents in `docs/game/`, linked from `qa-plan.md`, `metrics.md` and the README table.
- Read first: the vault note `research/2026-11-12-rendimiento-y-carga.md` (sections 2 to 4), `docs/performance.md`, ADR 0019 and 0032, `scripts/DocsCheck.luau`.
- Decision: no number is measured. Every row carries sourced, chosen or GAP; the "Medido" column is `TBD (#203)`.
- Checked against the official pages: the DataStore formula `60 + players x 40` per server and minute, and the 500 requests per second per client of RemoteEvent. The note's experience-level figure (10,300 reads per minute) does not follow from the 60-base formula (it would be 10,060), so it stays a GAP instead of being copied.
- Unit gap: the note says KB/s per player, `PerfBudget.runtime` says Kbps. The page keeps the config's unit and does not convert.
- Verified: stylua, selene, analyze, `lune run scripts/test`, docs-check, coverage, perf-budget and rojo build, all exit 0. A copy of both pages marked ready passes `docs-check 13`.
- Not verified: the procedure was not run with people. The Android Developer Console availability is stated as a fallback, not confirmed.
