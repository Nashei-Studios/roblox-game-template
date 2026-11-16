# 2026-11-15 Load and join limits in perf-budget

- Scope: issue #201, branch `feat/perf-gate-load-201`. Extends `scripts/perf-budget` and its existing CI step; no job added.
- Read first: ADR 0019 and 0032, `JoinPolicy`, `PlayerDataService`, the vault note `research/2026-11-12-rendimiento-y-carga.md` (sections 2 and 6, decision D3).
- Decision: ADR 0073. Pure rules in `LoadBudget`, limits in `PerfBudget.load`, each tagged sourced or chosen.
- Built: instance and part caps over a JSON place export, a simulated session-lock wait against `JoinPolicy.newWait`, a counting repository decorator for DataStore requests per join, 11 tests.
- Verified: stylua, selene, analyze, `lune run scripts/test`, docs-check, coverage, perf-budget and rojo build, all exit 0. The gate exits 1 with a limit lowered (session wait, DataStore) and with an over-cap export.
- Not verified: no place export exists in this repo, so the instance rule is skipped on the real repo and proven only with fixtures. Nothing produces the export yet. The caps are chosen, not measured.
