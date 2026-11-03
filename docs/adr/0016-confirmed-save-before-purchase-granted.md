# ADR 0016: Report a purchase as granted only after its save is confirmed; bounded ordered ledger

- Status: accepted by recommendation 2026-11-03, revisable
- Date: 2026-11-03
- Source: follow-up to the risk recorded in `docs/ai-logs/2026-11-03-migrations-and-grants.md` (D-38)

## Context

`ProcessReceipt` must return `PurchaseGranted` only when the purchase will not be lost. Until now the receipt was recorded in the player's in-memory data and Roblox was told `PurchaseGranted` immediately; a crash before the next autosave would lose both the grant and the ledger entry while Roblox considered the purchase done (the player paid and got nothing). Also, `PlayerData.purchases` was an unbounded map, so profiles grew with every purchase.

## What ProfileStore offers (verified, no invented API)

Sources: the vendored `vendor/ProfileStore/ProfileStore.luau` (pinned commit in `vendor/ProfileStore/README.md`) and the upstream docs (page "Developer Products", section "Caching PurchaseId's") read through context7 (`/madstudioroblox/profilestore`).

- `Profile.LastSavedData` ("Last snapshot of Profile.Data that has been successfully saved to the DataStore; Useful for proper developer product purchase receipt handling", header comment, line 97). It is assigned from the `UpdateAsync` result (line 877).
- `Profile.OnAfterSave` fires after a successful save (line 924, inside the branch where the session still owned the profile). `Profile:Save()` only spawns the save and returns nothing (lines 1172-1191), so there is no return value or callback to await; confirmation means observing `LastSavedData` or `OnAfterSave`.
- Official pattern: keep a bounded list of recent PurchaseIds in `Profile.Data`, apply the grant if the id is absent, then loop `Profile:Save()` / `OnAfterSave:Wait()` until `LastSavedData` contains the id or the session ends; return `PurchaseGranted` only in the first case.

Not available: a "save and wait" function, a save promise, or a way to confirm a specific write other than inspecting `LastSavedData`.

## Options considered

| Option | Loss-proof | Complexity | Notes |
|---|---|---|---|
| A. Keep: grant, record, return Granted at once | No (crash window up to one autosave period) | None | The risk being closed |
| B. `Profile:Save()` then return Granted | No: `Save()` is asynchronous and may fail or be coalesced | Low | False confirmation |
| C. Confirm through `LastSavedData` containing the PurchaseId, with a timeout (official pattern) | Yes for data that reached the DataStore | Medium: a port method and an adapter loop | Chosen |
| D. Separate DataStore for receipts | Yes | High: two stores that can disagree about the grant | Rejected: the grant and ledger must share one atomic profile write |

## Decision

Option C.

- Port `ProfileHandle<T>` gains `confirmSaved(isSaved, timeoutSeconds) -> Result<nil, "not_active" | "timeout">`. It yields until a confirmed snapshot satisfies `isSaved`. `PlayerDataService.confirmSaved(key, isSaved, timeout)` delegates to the player's handle (`not_active` when no data is loaded).
- Adapter `ProfileStoreRepository` implements it with the official loop: check `LastSavedData` first (it survives the end of the session, so a final save still confirms), then `IsActive`, then the deadline; it calls `Profile:Save()` at the start and again every 5 s (an in-flight save may predate the grant), polling every 0.1 s. Clock and wait are injected (`Runtime`) so the loop is tested under Lune with a fake clock.
- Pure `Monetization.processReceipt(ledger, receipt, grant, confirmSaved)` returns `granted` / `alreadyGranted` only when the save is confirmed, `unconfirmed` when delivered in memory but not confirmed, `failed` when not delivered. `MonetizationService` maps `failed` and `unconfirmed` to `NotProcessedYet` (Roblox retries) and the rest to `PurchaseGranted`.
- Decision on memory after a timeout: the PurchaseId stays recorded in memory. A retry then finds it, does not grant again, and only waits for the save. Proven by `ReceiptDelivery.test` (coins stay at the delivered amount after the retry).
- Config: `saveConfirmTimeoutSeconds` (default 30, validated positive) and `purchaseLedgerSize` (default 50, validated positive integer).
- Ledger shape: `purchases: { [string]: boolean }` becomes `purchaseIds: { string }`, oldest first, so the oldest can be dropped. Recording past `purchaseLedgerSize` removes the oldest ids. That is schema v3: step `v2 -> v3` in `PlayerDataMigrations` with golden fixture `tests/fixtures/playerdata/v3.luau`.

```mermaid
sequenceDiagram
    participant R as Roblox ProcessReceipt
    participant MS as MonetizationService
    participant M as Monetization.processReceipt
    participant PDS as PlayerDataService
    participant A as ProfileStoreRepository
    participant PS as ProfileStore
    R->>MS: receipt
    MS->>M: ledger, grant, confirmSaved
    M->>M: has(id)? if not, grant then record(id)
    M->>PDS: confirmSaved(user, id in saved.purchaseIds, timeout)
    PDS->>A: handle.confirmSaved
    loop until deadline or session end
        A->>PS: Save() (now, then every 5 s)
        A->>A: LastSavedData contains id?
    end
    alt confirmed
        A-->>MS: ok, PurchaseGranted
    else timeout or not active
        A-->>MS: error, NotProcessedYet (Roblox retries)
    end
```

## Consequences

- Positive: no purchase is reported done before it is in the DataStore; a failed or slow save causes a retry instead of a loss; the grant is never applied twice; profiles stop growing; the whole flow (including save outages) runs under Lune with fakes.
- Negative: `ProcessReceipt` yields up to `saveConfirmTimeoutSeconds` per receipt; a PurchaseId evicted from the window and retried later could be granted again (mitigation: the window of 50 far exceeds the receipts Roblox can leave pending, and the official example uses 100); the v2 ledger was an unordered map, so migrated entries are sorted by id, not by true age; `Profile:Save()` calls add DataStore writes (one per 5 s while waiting).
- Not verified without Studio / Execution API (R4, needs Victor's key): the real timing of `LastSavedData` updates, behavior when `UpdateAsync` is throttled, and the adapter against a real `ProfileStore`. Lune tests cover the logic with fakes only.

## What would change this decision

ProfileStore adding an awaitable save; Roblox changing the receipt retry or timeout semantics; real data showing more than the ledger window of unconfirmed receipts (then raise `purchaseLedgerSize`).
