--!strict
local Monetization = require("../../../src/shared/features/monetization/Monetization")
local harness = require("../../harness")

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

    suite:test("a list-backed ledger persists in the caller's list", function()
        local saved: { string } = {}
        local ledger = Monetization.newListLedger(saved, 50)
        Monetization.processReceipt(ledger, receipt("a"), function()
            return true
        end)
        harness.isTrue(table.find(saved, "a") ~= nil, "record lands in the player's data")
        local reloaded = Monetization.newListLedger(saved, 50)
        harness.isTrue(reloaded:has("a"), "a new ledger over the same list sees it")
    end)

    suite:test("a ledger past its capacity discards the oldest ids", function()
        local saved: { string } = {}
        local ledger = Monetization.newListLedger(saved, 3)
        for _, id in { "a", "b", "c", "d" } do
            ledger:record(id)
        end
        harness.equal(#saved, 3, "size stays bounded")
        harness.isFalse(ledger:has("a"), "oldest dropped")
        harness.isTrue(ledger:has("b") and ledger:has("c") and ledger:has("d"), "newest kept")
        harness.equal(saved[1], "b", "oldest first")
    end)

    suite:test("recording the same id twice keeps one entry", function()
        local saved: { string } = {}
        local ledger = Monetization.newListLedger(saved, 3)
        ledger:record("a")
        ledger:record("a")
        harness.equal(#saved, 1, "size")
    end)

    suite:test("a ledger already over capacity (legacy data) shrinks on the next record", function()
        local saved: { string } = { "a", "b", "c", "d", "e" }
        local ledger = Monetization.newListLedger(saved, 3)
        ledger:record("f")
        harness.equal(#saved, 3, "size")
        harness.equal(saved[3], "f", "newest last")
    end)
end
