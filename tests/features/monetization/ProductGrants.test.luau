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
        SeedBundle = { kind = "seeds", cropId = "carrot", amount = 10 },
        BadSeeds = { kind = "seeds", cropId = "carrot", amount = 0 },
        UnknownCrop = { kind = "seeds", cropId = "nope", amount = 5 },
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
        local data = { coins = 5, seeds = {} :: { [string]: number } }
        local result = newGrants():apply(data, "Coins100")
        harness.isTrue(result.ok, "applied")
        harness.equal(data.coins, 105, "coins")
    end)

    suite:test("an unknown product is a typed error and leaves data untouched", function()
        local data = { coins = 5, seeds = {} :: { [string]: number } }
        harness.equal(errorKind(newGrants():apply(data, "Nope")), "unknown_product")
        harness.equal(data.coins, 5, "coins")
    end)

    suite:test("invalid amounts are rejected without mutating data", function()
        local data = { coins = 5, seeds = {} :: { [string]: number } }
        harness.equal(errorKind(newGrants():apply(data, "Broken")), "invalid_amount", "negative")
        harness.equal(
            errorKind(newGrants():apply(data, "Fractional")),
            "invalid_amount",
            "fraction"
        )
        harness.equal(data.coins, 5, "coins")
    end)

    suite:test("overflow past MAX_COINS is rejected without mutating data", function()
        local data = { coins = 1, seeds = {} :: { [string]: number } }
        harness.equal(errorKind(newGrants():apply(data, "Huge")), "overflow")
        harness.equal(data.coins, 1, "coins")
    end)

    suite:test("the same PurchaseId through the ledger grants only once", function()
        local grants = newGrants()
        local data =
            { coins = 0, seeds = {} :: { [string]: number }, purchaseIds = {} :: { string } }
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
        local data =
            { coins = 0, seeds = {} :: { [string]: number }, purchaseIds = {} :: { string } }
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
    suite:test("a seeds product adds its fixed pack of that crop and leaves coins alone", function()
        local data = { coins = 5, seeds = { carrot = 2 } :: { [string]: number } }
        local result = newGrants():apply(data, "SeedBundle")
        harness.isTrue(result.ok, "applied")
        harness.equal(data.seeds.carrot, 12, "seeds")
        harness.equal(data.coins, 5, "coins untouched")
    end)

    suite:test("a seeds product past the stock cap is clamped and still granted", function()
        local data = { coins = 0, seeds = { carrot = 9995 } :: { [string]: number } }
        harness.isTrue(newGrants():apply(data, "SeedBundle").ok, "granted, never a retry loop")
        harness.equal(data.seeds.carrot, 9999, "clamped to MAX_STOCK")
    end)

    suite:test("a seeds grant with a bad amount or an unknown crop is a typed error", function()
        local data = { coins = 0, seeds = {} :: { [string]: number } }
        harness.equal(errorKind(newGrants():apply(data, "BadSeeds")), "invalid_amount", "amount")
        harness.equal(errorKind(newGrants():apply(data, "UnknownCrop")), "unknown_crop", "crop")
        harness.isTrue(next(data.seeds) == nil, "untouched")
    end)
end
