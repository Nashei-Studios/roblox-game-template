# Roadmap

| Phase | Goal | Exit criterion |
|---|---|---|
| R1 Template | Local template with toolchain, pure core, tests, CI, Studio MCP wiring | Template runs on Victor's PC: bootstrap all OK, `lune run scripts/test` green, `rojo serve` connects |
| R2 First prototype | A 48-72 h prototype built from the template on a dev place | Playable loop with the funnel events firing |
| R3 Soft launch | Published game with real ids, receipts and data sessions | Metrics read at 72 h; kill/iterate/scale verdict at day 7 |
| R4 Engine tests | Open Cloud Luau Execution API tests for adapters | Key created by Victor, tests run in CI |

Later: package manager ADR at the first dependency; revisit fully managed Rojo after the first game.
