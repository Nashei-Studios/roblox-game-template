--!strict
--[[
    Property-based tests over the economy and the receipt path (ADR 0062): invariants checked on
    hundreds of generated inputs, including the hostile ones (NaN, +-inf, 2^53, negatives).
    A failure prints its seed; replay it with `Prop.check(name, gen, property, { seed = N })`.
]]

local Config = require("../../src/shared/Config")
local Monetization = require("../../src/shared/features/monetization/Monetization")
local ProductGrants = require("../../src/shared/features/monetization/ProductGrants")
local Validation = require("../../src/shared/net/Validation")
local Prop = require("./Prop")
local harness = require("../harness")

local MAX_COINS = ProductGrants.MAX_COINS

local function isValidAmount(amount: number): boolean
    return amount == amount and amount > 0 and amount % 1 == 0 and amount <= MAX_COINS
end

local function isSaneBalance(coins: number): boolean
    return coins == coins and coins >= 0 and coins % 1 == 0 and coins <= MAX_COINS
end

type Purchase = { id: number, grantOk: boolean, savedOk: boolean }

local function purchaseGen(): Prop.Gen<Purchase>
    return Prop.make(function(rng: Prop.Rng): Purchase
        return {
            id = Prop.intBetween(rng, 1, 6),
            grantOk = Prop.chance(rng, 0.8),
            savedOk = Prop.chance(rng, 0.7),
        }
    end, function(value: Purchase): { Purchase }
        local candidates: { Purchase } = {}
        if value.id > 1 then
            table.insert(candidates, { id = 1, grantOk = value.grantOk, savedOk = value.savedOk })
        end
        if not value.grantOk then
            table.insert(candidates, { id = value.id, grantOk = true, savedOk = value.savedOk })
        end
        if not value.savedOk then
            table.insert(candidates, { id = value.id, grantOk = value.grantOk, savedOk = true })
        end
        return candidates
    end)
end

local PRODUCT_PRICE = 10

-- Replays `purchases` through processReceipt; returns the coins, how many times each id was
-- really granted and the ledger.
local function replay(
    purchases: { Purchase },
    capacity: number
): (number, { [number]: number }, Monetization.ReceiptLedger)
    local ledger = Monetization.newMemoryLedger(capacity)
    local coins = 0
    local granted: { [number]: number } = {}
    for _, purchase in purchases do
        Monetization.processReceipt(
            ledger,
            { playerId = 1, purchaseId = `p{purchase.id}`, productId = 1 },
            function(): boolean
                if not purchase.grantOk then
                    return false
                end
                coins += PRODUCT_PRICE
                granted[purchase.id] = (granted[purchase.id] or 0) + 1
                return true
            end,
            function(): boolean
                return purchase.savedOk
            end
        )
    end
    return coins, granted, ledger
end

local function shuffled<T>(list: { T }, seed: number): { T }
    local copy = table.clone(list)
    local rng = Prop.newRng(seed)
    for index = #copy, 2, -1 do
        local other = Prop.intBetween(rng, 1, index)
        copy[index], copy[other] = copy[other], copy[index]
    end
    return copy
end

return function(suite: harness.Harness)
    suite:test("property: the balance is never negative, NaN or above the cap", function()
        local gen = Prop.pair(Prop.integer(0, MAX_COINS), Prop.listOf(Prop.number(), 12))
        Prop.check("balance stays sane", gen, function(input)
            local data = { coins = input.a }
            for _, amount in input.b do
                local grants = ProductGrants.new({ P = { kind = "coins", amount = amount } })
                local before = data.coins
                local result = grants:apply(data, "P")
                harness.isTrue(isSaneBalance(data.coins), `balance {data.coins} after {amount}`)
                if result.ok then
                    harness.equal(data.coins, before + amount, "adds exactly the amount")
                else
                    harness.equal(data.coins, before, "a rejected grant leaves the data alone")
                end
            end
        end)
    end)

    suite:test("property: an unknown product never changes the balance", function()
        local gen = Prop.pair(Prop.string(), Prop.integer(0, 1000))
        Prop.check("unknown product", gen, function(input)
            local grants = ProductGrants.new({ Coins100 = { kind = "coins", amount = 100 } })
            local data = { coins = input.b }
            local result = grants:apply(data, input.a)
            if input.a ~= "Coins100" then
                harness.isFalse(result.ok, "unknown name rejected")
                harness.equal(data.coins, input.b, "balance untouched")
            end
        end)
    end)

    suite:test("property: a grant amount out of range is rejected, in range is accepted", function()
        Prop.check("grant amount range", Prop.number(), function(amount: number)
            local data = { coins = 0 }
            local grants = ProductGrants.new({ P = { kind = "coins", amount = amount } })
            harness.equal(grants:apply(data, "P").ok, isValidAmount(amount), `apply of {amount}`)
        end)
    end)

    suite:test("property: Config.validate flags exactly the amounts the grant rejects", function()
        Prop.check("config amount agrees with grants", Prop.number(), function(amount: number)
            local config = table.clone(Config.default)
            config.developerProducts = {
                { name = "Probe", id = 1, grant = { kind = "coins", amount = amount } },
            }
            local flagged = false
            for _, problem in Config.validate(config) do
                if string.find(problem, "invalid amount", 1, true) ~= nil then
                    flagged = true
                end
            end
            harness.equal(flagged, not isValidAmount(amount), `validate verdict for {amount}`)
        end)
    end)

    suite:test("regression: Config.validate rejects a coins grant above 2^53", function()
        -- Found by the property above (ADR 0062): validate used to accept 1e300 coins while
        -- ProductGrants refused to apply it, so the player paid Robux and got nothing.
        local config = table.clone(Config.default)
        config.developerProducts = {
            { name = "Huge", id = 1, grant = { kind = "coins", amount = 2 ^ 53 + 2 } },
        }
        local flagged = false
        for _, problem in Config.validate(config) do
            flagged = flagged or string.find(problem, "invalid amount", 1, true) ~= nil
        end
        harness.isTrue(flagged, "an amount above 2^53 is a config problem")
        harness.equal(Config.MAX_GRANT_COINS, ProductGrants.MAX_COINS, "caps agree")
    end)

    suite:test("property: integerInRange accepts exactly the finite integers in range", function()
        local gen = Prop.pair(Prop.number(), Prop.pair(Prop.integer(-50, 50), Prop.integer(0, 100)))
        Prop.check("quantity range", gen, function(input)
            local low = input.b.a
            local high = low + input.b.b
            local value = input.a
            local expected = value == value
                and value ~= math.huge
                and value ~= -math.huge
                and value % 1 == 0
                and value >= low
                and value <= high
            harness.equal(Validation.integerInRange(value, low, high).ok, expected, "verdict")
        end)
    end)

    suite:test("property: a repeated PurchaseId is granted at most once", function()
        Prop.check("receipt idempotency", Prop.listOf(purchaseGen(), 40), function(purchases)
            local coins, granted = replay(purchases, 100)
            local total = 0
            for id, times in granted do
                harness.isTrue(times <= 1, `purchase p{id} granted {times} times`)
                total += times
            end
            harness.equal(coins, total * PRODUCT_PRICE, "coins equal grants times price")
        end)
    end)

    suite:test(
        "property: a failed grant is never recorded, a recorded one never regranted",
        function()
            Prop.check("receipt decisions", Prop.listOf(purchaseGen(), 40), function(purchases)
                local ledger = Monetization.newMemoryLedger(100)
                for _, purchase in purchases do
                    local purchaseId = `p{purchase.id}`
                    local wasRecorded = ledger:has(purchaseId)
                    local decision = Monetization.processReceipt(
                        ledger,
                        { playerId = 1, purchaseId = purchaseId, productId = 1 },
                        function(): boolean
                            return purchase.grantOk
                        end,
                        function(): boolean
                            return purchase.savedOk
                        end
                    )
                    if wasRecorded then
                        harness.isTrue(
                            decision == "alreadyGranted" or decision == "unconfirmed",
                            "a recorded id is never granted again"
                        )
                    elseif not purchase.grantOk then
                        harness.equal(decision, "failed", "grant failure")
                        harness.isFalse(ledger:has(purchaseId), "a failed grant is not recorded")
                    end
                    if decision == "granted" or decision == "alreadyGranted" then
                        harness.isTrue(purchase.savedOk, "only a confirmed save reports success")
                    end
                end
            end)
        end
    )

    suite:test("property: event order and repeats do not change the total", function()
        local gen = Prop.pair(Prop.listOf(purchaseGen(), 30), Prop.integer(0, 1000000))
        Prop.check("receipt order independence", gen, function(input)
            -- Every attempt succeeds, so the outcome depends only on which ids were seen.
            local clean: { Purchase } = {}
            for _, purchase in input.a do
                table.insert(clean, { id = purchase.id, grantOk = true, savedOk = true })
            end
            local coinsA, _, ledgerA = replay(clean, 100)
            local coinsB, _, ledgerB = replay(shuffled(clean, input.b), 100)
            harness.equal(coinsA, coinsB, "same total after a shuffle")
            local distinct: { [number]: boolean } = {}
            for _, purchase in clean do
                distinct[purchase.id] = true
            end
            local count = 0
            for id in distinct do
                count += 1
                harness.isTrue(ledgerA:has(`p{id}`) and ledgerB:has(`p{id}`), "both record the id")
            end
            harness.equal(coinsA, count * PRODUCT_PRICE, "one price per distinct id")
        end)
    end)

    suite:test("property: the order of valid grants does not change the balance", function()
        local gen = Prop.pair(Prop.listOf(Prop.integer(1, 1000000), 20), Prop.integer(0, 1000000))
        Prop.check("grant order independence", gen, function(input)
            local function total(amounts: { number }): number
                local data = { coins = 0 }
                for _, amount in amounts do
                    local grants = ProductGrants.new({ P = { kind = "coins", amount = amount } })
                    grants:apply(data, "P")
                end
                return data.coins
            end
            harness.equal(total(input.a), total(shuffled(input.a, input.b)), "same balance")
        end)
    end)
end
