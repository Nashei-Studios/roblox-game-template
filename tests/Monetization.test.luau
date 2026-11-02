--!strict
local Monetization = require("../src/shared/Monetization")
local harness = require("./harness")

local function receipt(purchaseId: string): Monetization.ReceiptInfo
    return { playerId = 1, purchaseId = purchaseId, productId = 10 }
end

return function(suite: harness.Harness)
    suite:test("grants a new purchase once", function()
        local ledger = Monetization.newMemoryLedger()
        local grants = 0
        local decision = Monetization.processReceipt(ledger, receipt("a"), function()
            grants += 1
            return true
        end)
        harness.equal(decision, "granted")
        harness.equal(grants, 1, "grant calls")
    end)

    suite:test("does not grant the same PurchaseId twice (idempotent)", function()
        local ledger = Monetization.newMemoryLedger()
        local grants = 0
        local function grant(): boolean
            grants += 1
            return true
        end
        Monetization.processReceipt(ledger, receipt("a"), grant)
        local second = Monetization.processReceipt(ledger, receipt("a"), grant)
        harness.equal(second, "alreadyGranted")
        harness.equal(grants, 1, "grant calls")
    end)

    suite:test("a failed grant is not recorded, so the receipt can retry", function()
        local ledger = Monetization.newMemoryLedger()
        local first = Monetization.processReceipt(ledger, receipt("a"), function()
            return false
        end)
        harness.equal(first, "failed")
        harness.isFalse(ledger:has("a"), "ledger has failed purchase")
        local retry = Monetization.processReceipt(ledger, receipt("a"), function()
            return true
        end)
        harness.equal(retry, "granted")
    end)
end
