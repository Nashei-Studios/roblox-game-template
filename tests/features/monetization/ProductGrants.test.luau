--!strict
local Monetization = require("../../../src/shared/features/monetization/Monetization")
local ProductGrants = require("../../../src/shared/features/monetization/ProductGrants")
local harness = require("../../harness")

-- Confirms every save: these tests cover delivery and idempotency, not persistence.
local function process(
    ledger: Monetization.ReceiptLedger,
    receipt: Monetization.ReceiptInfo,
    grant: Monetization.GrantFn
): Monetization.ReceiptDecision
    return Monetization.processReceipt(ledger, receipt, grant, function(): boolean
        return true
    end)
end

local function newGrants(): ProductGrants.ProductGrants
    return ProductGrants.new({
        Coins100 = { kind = "coins", amount = 100 },
        Broken = { kind = "coins", amount = -5 },
        Fractional = { kind = "coins", amount = 1.5 },
        SkipStage = { kind = "skipStage", maxStage = 3 },
        BadSkip = { kind = "skipStage", maxStage = 0 },
        Huge = { kind = "coins", amount = ProductGrants.MAX_COINS },
    })
end

local function errorKind(result: ProductGrants.GrantResult): string
    if result.ok then
        return "none"
    end
    return result.error.kind
end

return function(suite: harness.Harness)
    suite:test("a coins product adds its amount to the player's coins", function()
        local data = { coins = 5, highestStage = 0 }
        local result = newGrants():apply(data, "Coins100")
        harness.isTrue(result.ok, "applied")
        harness.equal(data.coins, 105, "coins")
    end)

    suite:test("an unknown product is a typed error and leaves data untouched", function()
        local data = { coins = 5, highestStage = 0 }
        harness.equal(errorKind(newGrants():apply(data, "Nope")), "unknown_product")
        harness.equal(data.coins, 5, "coins")
    end)

    suite:test("invalid amounts are rejected without mutating data", function()
        local data = { coins = 5, highestStage = 0 }
        harness.equal(errorKind(newGrants():apply(data, "Broken")), "invalid_amount", "negative")
        harness.equal(
            errorKind(newGrants():apply(data, "Fractional")),
            "invalid_amount",
            "fraction"
        )
        harness.equal(data.coins, 5, "coins")
    end)

    suite:test("overflow past MAX_COINS is rejected without mutating data", function()
        local data = { coins = 1, highestStage = 0 }
        harness.equal(errorKind(newGrants():apply(data, "Huge")), "overflow")
        harness.equal(data.coins, 1, "coins")
    end)

    suite:test("the same PurchaseId through the ledger grants only once", function()
        local grants = newGrants()
        local data = { coins = 0, highestStage = 0, purchaseIds = {} :: { string } }
        local ledger = Monetization.newListLedger(data.purchaseIds, 50)
        local function grant(): boolean
            return grants:apply(data, "Coins100").ok
        end
        local receipt: Monetization.ReceiptInfo =
            { playerId = 1, purchaseId = "p-1", productId = 10 }
        harness.equal(process(ledger, receipt, grant), "granted", "first")
        harness.equal(process(ledger, receipt, grant), "alreadyGranted", "second")
        harness.equal(data.coins, 100, "delivered once")
    end)

    suite:test("a failed grant is not recorded, so Roblox can retry the receipt", function()
        local grants = newGrants()
        local data = { coins = 0, highestStage = 0, purchaseIds = {} :: { string } }
        local ledger = Monetization.newListLedger(data.purchaseIds, 50)
        local receipt: Monetization.ReceiptInfo =
            { playerId = 1, purchaseId = "p-2", productId = 10 }
        local decision = process(ledger, receipt, function(): boolean
            return grants:apply(data, "Nope").ok
        end)
        harness.equal(decision, "failed")
        harness.isFalse(ledger:has("p-2"), "not recorded")
        harness.equal(data.coins, 0, "no delivery")
    end)

    suite:test("a skipStage product clears the next stage", function()
        local data = { coins = 5, highestStage = 1 }
        local result = newGrants():apply(data, "SkipStage")
        harness.isTrue(result.ok, "applied")
        harness.equal(data.highestStage, 2, "stage")
        harness.equal(data.coins, 5, "coins untouched")
    end)

    suite:test("skipStage at the last stage is a granted no-op, never a failed receipt", function()
        local data = { coins = 5, highestStage = 3 }
        harness.isTrue(newGrants():apply(data, "SkipStage").ok, "granted")
        harness.equal(data.highestStage, 3, "clamped to maxStage")
    end)

    suite:test("a skipStage grant with a bad maxStage is a typed error", function()
        local data = { coins = 5, highestStage = 0 }
        harness.equal(errorKind(newGrants():apply(data, "BadSkip")), "invalid_amount", "bad")
        harness.equal(data.highestStage, 0, "untouched")
    end)
end
