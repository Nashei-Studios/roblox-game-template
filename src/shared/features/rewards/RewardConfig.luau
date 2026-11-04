--!strict
--[[
    Shared validation of a reward declared in Config (codes, daily rewards, session gifts).
    Rewards have the shape of a developer-product grant, so delivery goes through the existing
    grant path (`features/monetization/ProductGrants`). Pure: loads under Lune.
]]

local ProductGrants = require("../monetization/ProductGrants")

export type Reward = ProductGrants.ProductGrant

local RewardConfig = {}

--- One problem per invalid field of `reward`; `label` names it in the message.
function RewardConfig.problems(reward: Reward, label: string): { string }
    local problems: { string } = {}
    if reward.kind ~= "coins" then
        table.insert(problems, `{label} has an unknown reward kind`)
        return problems
    end
    local amount = reward.amount
    if amount ~= amount or amount <= 0 or amount % 1 ~= 0 or amount > ProductGrants.MAX_COINS then
        table.insert(problems, `{label} has an invalid amount (must be a positive integer)`)
    end
    return problems
end

--- True when `value` is a finite number (not NaN, not infinite).
function RewardConfig.isFinite(value: number): boolean
    return value == value and value ~= math.huge and value ~= -math.huge
end

--- True when `value` is an integer of at least 1.
function RewardConfig.isPositiveInteger(value: number): boolean
    return RewardConfig.isFinite(value) and value >= 1 and value % 1 == 0
end

return RewardConfig
