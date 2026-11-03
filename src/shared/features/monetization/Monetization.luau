--!strict
--[[
    Pure receipt-processing core (idempotent ProcessReceipt pattern).
    No Roblox services: the server service in src/server/features/monetization/MonetizationService.luau maps
    the result to Enum.ProductPurchaseDecision.

    Rule: a purchase is granted at most once per PurchaseId. A failed grant is NOT
    recorded, so Roblox retries the receipt on the next join.
]]

export type ReceiptInfo = {
    playerId: number,
    purchaseId: string,
    productId: number,
}

export type ReceiptDecision = "granted" | "alreadyGranted" | "failed"

-- Storage for processed purchase ids. Production code backs this with the player's
-- persisted data (see PlayerData.luau and newListLedger); tests use the in-memory ledger.
export type ReceiptLedger = {
    has: (self: ReceiptLedger, purchaseId: string) -> boolean,
    record: (self: ReceiptLedger, purchaseId: string) -> (),
}

-- Grants the product. Returns true only when the grant fully succeeded.
export type GrantFn = (receipt: ReceiptInfo) -> boolean

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

function Monetization.processReceipt(
    ledger: ReceiptLedger,
    receipt: ReceiptInfo,
    grant: GrantFn
): ReceiptDecision
    if ledger:has(receipt.purchaseId) then
        return "alreadyGranted"
    end
    local granted = grant(receipt)
    if not granted then
        return "failed"
    end
    ledger:record(receipt.purchaseId)
    return "granted"
end

return Monetization
