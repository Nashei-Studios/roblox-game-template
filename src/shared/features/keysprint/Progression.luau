--!strict
--[[
    Pure progression rules (ADR 0020): which stage a player starts, what a clear pays, and what
    the next cap costs. Every price and reward is derived here from KeySprintRules; a remote
    never carries one. Functions mutate the `Target` slice of the player data in place and are
    all-or-nothing: a refusal changes nothing.
]]

local KeySprintRules = require("./KeySprintRules")
local ProductGrants = require("../monetization/ProductGrants")

-- The slice of PlayerData this module reads and writes.
export type Target = { coins: number, highestStage: number, multiplierCap: number }

export type FinishOutcome = { coinsAwarded: number, firstClear: boolean }

export type BuyCapResult =
    { ok: true, newCap: number, price: number }
    | { ok: false, reason: "max_cap" | "not_enough_coins" }

local Progression = {}

--- The stage a player is placed in: the first uncleared one, or the last when all are cleared.
function Progression.startStage(target: Target): number
    return math.min(target.highestStage + 1, KeySprintRules.STAGE_COUNT)
end

function Progression.isComplete(target: Target): boolean
    return target.highestStage >= KeySprintRules.STAGE_COUNT
end

--- Pays the reward of `stage` and advances highestStage when it is a first clear.
function Progression.applyFinish(target: Target, stage: number): FinishOutcome
    local reward = KeySprintRules.STAGE_REWARDS[stage]
    if reward == nil then
        return { coinsAwarded = 0, firstClear = false }
    end
    target.coins = math.min(ProductGrants.MAX_COINS, target.coins + reward)
    local firstClear = stage > target.highestStage
    if firstClear then
        target.highestStage = stage
    end
    return { coinsAwarded = reward, firstClear = firstClear }
end

--- Coins needed to raise `cap` one step; nil at the maximum (or off the price table).
function Progression.nextCapPrice(cap: number): number?
    if cap >= KeySprintRules.MAX_CAP then
        return nil
    end
    return KeySprintRules.CAP_PRICES[cap]
end

function Progression.buyCap(target: Target): BuyCapResult
    local price = Progression.nextCapPrice(target.multiplierCap)
    if price == nil then
        return { ok = false, reason = "max_cap" }
    end
    if target.coins < price then
        return { ok = false, reason = "not_enough_coins" }
    end
    target.coins -= price
    target.multiplierCap =
        math.min(KeySprintRules.MAX_CAP, target.multiplierCap + KeySprintRules.CAP_STEP)
    return { ok = true, newCap = target.multiplierCap, price = price }
end

return Progression
