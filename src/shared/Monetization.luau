--!strict
--[[
    Pure receipt-processing core (idempotent ProcessReceipt pattern).
    No Roblox services: the server adapter in src/server/MonetizationService.luau maps
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
-- persisted data (see Session.luau); tests use the in-memory ledger below.
export type ReceiptLedger = {
    has: (self: ReceiptLedger, purchaseId: string) -> boolean,
    record: (self: ReceiptLedger, purchaseId: string) -> (),
}

-- Grants the product. Returns true only when the grant fully succeeded.
export type GrantFn = (receipt: ReceiptInfo) -> boolean

local Monetization = {}

function Monetization.newMemoryLedger(): ReceiptLedger
    local seen: { [string]: boolean } = {}
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
