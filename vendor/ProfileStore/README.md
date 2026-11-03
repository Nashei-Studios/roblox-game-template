# vendor/ProfileStore

Vendored, unmodified copy of ProfileStore by MAD STUDIO (loleris / MadStudioRoblox). Used behind the `ProfileRepository` port ([ADR 0010](../../docs/adr/0010-profilestore-behind-profilerepository.md)). Never edit `ProfileStore.luau`; to update, replace it and update this table.

| Field | Value |
|---|---|
| Upstream | https://github.com/MadStudioRoblox/ProfileStore |
| Pinned commit | `45c9847cbcf1fc260369c50eb335aba7c35aecdd` (last upstream push 2025-07-31) |
| Files copied | `ProfileStore.luau` (64,654 bytes), `LICENSE` (11,357 bytes) |
| Fetched | 2026-11-02 with `gh api repos/MadStudioRoblox/ProfileStore/contents/<file>?ref=<commit>` |
| License | Apache-2.0 (`LICENSE` in this folder, unmodified) |
| NOTICE | The upstream repository has no `NOTICE` file at that commit, so none is carried. |

## Review before vendoring (2026-11-02)

The whole 2,243-line `ProfileStore.luau` was read as data before it entered the repo. What it does: wraps `DataStoreService` (`UpdateAsync`, `GetAsync`, `GetVersionAsync`, `ListVersionsAsync`, `RemoveAsync`) with session locking; uses `MessagingService` only for the `PS_<session id>` topic that asks another server to release a profile; `HttpService:GenerateGUID` for session ids; `RunService.Heartbeat` for autosave; `game:BindToClose` to release profiles on shutdown. It makes no HTTP requests, no `loadstring`, no `require` of other modules and reads no other game data. It also touches a DataStore key `____PS` in Studio to detect API access.

## How it is wired

- Rojo maps the file to `ServerScriptService.Vendor.ProfileStore` (`default.project.json`).
- Only `src/server/adapters/ProfileStoreRepository.luau` and `src/server/Main.server.luau` know about it. The rest of the code uses the `ProfileRepository` port.
- StyLua, Selene and `luau-lsp analyze` skip this folder (`.styluaignore`, `selene.toml`, `vendor/.luaurc` sets `nocheck`).

## Known limits to remember

- Not meant for leaderboards or global state (use OrderedDataStore, MemoryStore or Open Cloud).
- Profile data must be JSON-serializable: no Instances, userdata, functions, sparse or mixed tables.
- `Profile:Save()` is asynchronous; failures surface through `ProfileStore.OnError` (not wired in the template yet).
