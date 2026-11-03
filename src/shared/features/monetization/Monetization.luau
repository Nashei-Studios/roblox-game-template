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
-- persisted data (see PlayerData.luau and newTableLedger); tests use the in-memory ledger.
export type ReceiptLedger = {
    has: (self: ReceiptLedger, purchaseId: string) -> boolean,
    record: (self: ReceiptLedger, purchaseId: string) -> (),
}

-- Grants the product. Returns true only when the grant fully succeeded.
export type GrantFn = (receipt: ReceiptInfo) -> boolean

local Monetization = {}

--- Ledger over a caller-owned table (the player's saved data), so records persist with the profile.
function Monetization.newTableLedger(seen: { [string]: boolean }): ReceiptLedger
    local ledger: ReceiptLedger = {
        has = function(_self: ReceiptLedger, purchaseId: string): boolean
            return seen[purchaseId] == true
        end,
        record = function(_self: ReceiptLedger, purchaseId: string)
            seen[purchaseId] = true
        end,
    }
    return ledger
end

function Monetization.newMemoryLedger(): ReceiptLedger
    return Monetization.newTableLedger({})
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
