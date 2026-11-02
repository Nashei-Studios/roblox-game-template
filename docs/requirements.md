# Requirements

## Functional
- FR-1 Config module with typed game passes and developer products; unset ids are reported, never faked.
- FR-2 Data session wrapper with server lock, stale-lock takeover, save and release, returning typed Results.
- FR-3 Idempotent receipt processing: one grant per PurchaseId; failed grants retry.
- FR-4 Funnel event names and a pure event builder.
- FR-5 Rojo project mapping Shared, Server and Client; Studio owns world, terrain and UI.

## Non-functional
- NFR-1 Type safety: `--!strict` in every file, no `any`, typed exports.
- NFR-2 Testability: business logic runs under Lune with no engine; coverage of the pure modules is by behavior tests (no coverage tool yet; target 75 % once one is chosen).
- NFR-3 Reproducibility: pinned toolchain in `rokit.toml`; setup runnable by someone who was not there (`scripts/bootstrap.ps1`).
- NFR-4 Security: no secrets in the repo; Studio MCP built-in only, dev place only; no real-money actions.
- NFR-5 Cost: CI under 10 minutes per run, triggered only on PR and push to main.
- NFR-6 Data safety: a save by a non-owner server is rejected; data is not overwritten by a stale session.
