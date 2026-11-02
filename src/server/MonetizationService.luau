--!strict
--[[
    Adapter: wires MarketplaceService.ProcessReceipt to the pure core in
    Monetization.luau. A real game supplies `getLedger` (backed by the player's
    persisted data) and `grant`. Real-money flows are the developer's responsibility:
    test only on a dev place and never mark a receipt processed before the grant is saved.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Monetization)

export type Deps = {
    -- nil when the player's data is not loaded yet (the purchase stays unprocessed).
    getLedger: (userId: number) -> Monetization.ReceiptLedger?,
    grant: Monetization.GrantFn,
}

local MonetizationService = {}

function MonetizationService.start(deps: Deps)
    MarketplaceService.ProcessReceipt = function(info: {
        PlayerId: number,
        PurchaseId: string,
        ProductId: number,
    }): Enum.ProductPurchaseDecision
        local ledger = deps.getLedger(info.PlayerId)
        if ledger == nil then
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end
        local receipt: Monetization.ReceiptInfo = {
            playerId = info.PlayerId,
            purchaseId = info.PurchaseId,
            productId = info.ProductId,
        }
        local decision = Monetization.processReceipt(ledger, receipt, deps.grant)
        if decision == "failed" then
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end
end

return MonetizationService
