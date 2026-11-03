--!strict
--[[
    Feature service: wires MarketplaceService.ProcessReceipt to the pure core in
    shared/features/monetization/Monetization.luau. Dependencies are injected; the composition
    root (Main.server) supplies the ledger provider (backed by the player's profile) and `grant`.
    Real-money flows are the developer's responsibility: test only on a dev place and never
    mark a receipt processed before the grant is saved.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.features.monetization.Monetization)
local LedgerProvider = require(ReplicatedStorage.Shared.ports.LedgerProvider)

export type Deps = {
    ledgers: LedgerProvider.LedgerProvider,
    grant: Monetization.GrantFn,
}

export type MonetizationService = {
    -- Sets the single ProcessReceipt callback (Roblox allows exactly one, from one script).
    start: () -> (),
}

local MonetizationServiceModule = {}

function MonetizationServiceModule.new(deps: Deps): MonetizationService
    local service: MonetizationService = {
        start = function()
            MarketplaceService.ProcessReceipt = function(
                info: {
                    PlayerId: number,
                    PurchaseId: string,
                    ProductId: number,
                }
            ): Enum.ProductPurchaseDecision
                local ledger = deps.ledgers:ledgerFor(info.PlayerId)
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
        end,
    }
    return service
end

return MonetizationServiceModule
