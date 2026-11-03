--!strict
--[[
    Pure receipt-processing core (idempotent ProcessReceipt pattern).
    No Roblox services: the server service in src/server/features/monetization/MonetizationService.luau maps
    the result to Enum.ProductPurchaseDecision.

    Rule: a purchase is granted at most once per PurchaseId. A failed grant is NOT
    recorded, and a grant whose save is not confirmed is reported as unconfirmed, so Roblox
    retries the receipt (ADR 0016).
]]

export type ReceiptInfo = {
    playerId: number,
    purchaseId: string,
    productId: number,
}

-- granted: delivered now and confirmed saved. alreadyGranted: delivered earlier and confirmed
-- saved. unconfirmed: delivered in memory but the save was not confirmed (retry later).
-- failed: not delivered. Only "granted" and "alreadyGranted" may become PurchaseGranted.
export type ReceiptDecision = "granted" | "alreadyGranted" | "unconfirmed" | "failed"

-- Storage for processed purchase ids. Production code backs this with the player's
-- persisted data (see PlayerData.luau and newListLedger); tests use the in-memory ledger.
export type ReceiptLedger = {
    has: (self: ReceiptLedger, purchaseId: string) -> boolean,
    record: (self: ReceiptLedger, purchaseId: string) -> (),
}

-- Grants the product. Returns true only when the grant fully succeeded.
export type GrantFn = (receipt: ReceiptInfo) -> boolean

-- Yields until the data holding this PurchaseId (and the grant) is confirmed saved; false when
-- the player left, the session ended, or the save did not land in time.
export type ConfirmSavedFn = (purchaseId: string) -> boolean

local Monetization = {}

--- Bounded ledger over a caller-owned list (the player's saved `purchaseIds`, oldest first),
--- so records persist with the profile. Recording past `capacity` discards the oldest ids; a
--- receipt older than that window could in theory be granted again, so keep `capacity` well
--- above the number of purchases Roblox can leave unconfirmed (ADR 0016).
function Monetization.newListLedger(ids: { string }, capacity: number): ReceiptLedger
    local ledger: ReceiptLedger = {
        has = function(_self: ReceiptLedger, purchaseId: string): boolean
            return table.find(ids, purchaseId) ~= nil
        end,
        record = function(_self: ReceiptLedger, purchaseId: string)
            if table.find(ids, purchaseId) ~= nil then
                return
            end
            while #ids >= math.max(capacity, 1) do
                table.remove(ids, 1)
            end
            table.insert(ids, purchaseId)
        end,
    }
    return ledger
end

function Monetization.newMemoryLedger(capacity: number?): ReceiptLedger
    return Monetization.newListLedger({}, capacity or 50)
end

--- Rule: the grant and the ledger entry live in the same saved data, so a purchase is reported
--- as processed only once that data is confirmed saved. If the grant is applied but the save
--- is not confirmed, the entry stays in memory: Roblox retries the receipt, `has` is true, the
--- grant is NOT applied twice, and the retry only waits for the save again.
function Monetization.processReceipt(
    ledger: ReceiptLedger,
    receipt: ReceiptInfo,
    grant: GrantFn,
    confirmSaved: ConfirmSavedFn
): ReceiptDecision
    local alreadyDelivered = ledger:has(receipt.purchaseId)
    if not alreadyDelivered then
        if not grant(receipt) then
            return "failed"
        end
        ledger:record(receipt.purchaseId)
    end
    if not confirmSaved(receipt.purchaseId) then
        return "unconfirmed"
    end
    return if alreadyDelivered then "alreadyGranted" else "granted"
end

return Monetization
