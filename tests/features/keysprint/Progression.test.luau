--!strict
local KeySprintRules = require("../../../src/shared/features/keysprint/KeySprintRules")
local Progression = require("../../../src/shared/features/keysprint/Progression")
local harness = require("../../harness")

local function data(coins: number, highestStage: number, cap: number): Progression.Target
    return { coins = coins, highestStage = highestStage, multiplierCap = cap }
end

return function(suite: harness.Harness)
    suite:test("startStage is the next uncleared stage, never past the last", function()
        harness.equal(Progression.startStage(data(0, 0, 5)), 1, "new player")
        harness.equal(Progression.startStage(data(0, 1, 5)), 2, "after stage 1")
        harness.equal(Progression.startStage(data(0, 3, 5)), 3, "all cleared: replay the last")
    end)

    suite:test("the first clear pays the reward and advances highestStage", function()
        local target = data(0, 0, 5)
        local outcome = Progression.applyFinish(target, 1)
        harness.equal(outcome.coinsAwarded, KeySprintRules.STAGE_REWARDS[1], "reward")
        harness.isTrue(outcome.firstClear, "first clear")
        harness.equal(target.highestStage, 1, "highestStage")
        harness.equal(target.coins, KeySprintRules.STAGE_REWARDS[1], "coins")
    end)

    suite:test("a replay pays the reward without moving highestStage", function()
        local target = data(10, 2, 5)
        local outcome = Progression.applyFinish(target, 1)
        harness.isFalse(outcome.firstClear, "replay")
        harness.equal(target.highestStage, 2, "unchanged")
        harness.equal(target.coins, 10 + KeySprintRules.STAGE_REWARDS[1], "coins")
    end)

    suite:test("coins never pass MAX_COINS", function()
        local target = data(2 ^ 53 - 1, 0, 5)
        Progression.applyFinish(target, 1)
        harness.equal(target.coins, 2 ^ 53, "clamped")
    end)

    suite:test("an unknown stage awards nothing", function()
        local target = data(0, 0, 5)
        local outcome = Progression.applyFinish(target, 99)
        harness.equal(outcome.coinsAwarded, 0, "nothing")
        harness.equal(target.coins, 0, "coins")
        harness.equal(target.highestStage, 0, "stage")
    end)

    suite:test("nextCapPrice follows the table and is nil at the maximum", function()
        harness.equal(Progression.nextCapPrice(5), KeySprintRules.CAP_PRICES[5], "5 -> 10")
        harness.equal(Progression.nextCapPrice(25), KeySprintRules.CAP_PRICES[25], "25 -> 30")
        harness.isTrue(Progression.nextCapPrice(KeySprintRules.MAX_CAP) == nil, "max")
    end)

    suite:test("every cap level up to the maximum has a price", function()
        local cap = KeySprintRules.BASE_CAP
        while cap < KeySprintRules.MAX_CAP do
            harness.isTrue(Progression.nextCapPrice(cap) ~= nil, `price for cap {cap}`)
            cap += KeySprintRules.CAP_STEP
        end
    end)

    suite:test("buyCap spends the server price and raises the cap by one step", function()
        local target = data(100, 0, 5)
        local result = Progression.buyCap(target)
        harness.isTrue(result.ok, "bought")
        harness.equal(target.multiplierCap, 10, "cap")
        harness.equal(target.coins, 100 - (KeySprintRules.CAP_PRICES[5] :: number), "coins")
    end)

    suite:test("buyCap with too few coins changes nothing", function()
        local target = data(10, 0, 5)
        local result = Progression.buyCap(target)
        harness.isFalse(result.ok, "refused")
        if not result.ok then
            harness.equal(result.reason, "not_enough_coins", "reason")
        end
        harness.equal(target.coins, 10, "coins")
        harness.equal(target.multiplierCap, 5, "cap")
    end)

    suite:test("buyCap at the maximum is refused", function()
        local target = data(1e9, 0, KeySprintRules.MAX_CAP)
        local result = Progression.buyCap(target)
        harness.isFalse(result.ok, "refused")
        if not result.ok then
            harness.equal(result.reason, "max_cap", "reason")
        end
        harness.equal(target.coins, 1e9, "coins")
    end)

    suite:test("a cap that is off the price table is treated as the maximum", function()
        local result = Progression.buyCap(data(1e9, 0, 7))
        harness.isFalse(result.ok, "refused")
    end)

    suite:test("isComplete is true once every stage is cleared", function()
        harness.isFalse(Progression.isComplete(data(0, 2, 5)), "two of three")
        harness.isTrue(Progression.isComplete(data(0, 3, 5)), "all")
    end)
end
