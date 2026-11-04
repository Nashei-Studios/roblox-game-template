--!strict
--[[
    Typed config of the community join reward and its validation. Pure: loads under Lune.
    Ships disabled: whether a game may reward joining a community is an open [GAP] in the vault
    research (no official rule found), so enabling it needs Victor to confirm the Community
    Standards and Terms text first. Rewards are never Robux-denominated.
]]

local RewardConfig = require("../rewards/RewardConfig")

export type CommunityRewardConfig = {
    enabled: boolean,
    -- The Roblox community (group) id. nil until the game sets it.
    communityId: number?,
    -- One-time, non-Robux reward. nil until the game sets it.
    reward: RewardConfig.Reward?,
    -- Minimum seconds between two membership checks for the same player (join check included).
    recheckCooldownSeconds: number,
    -- Offer the platform join prompt from the UI.
    promptJoin: boolean,
}

local CommunityRewardConfigModule = {}

--- One human-readable problem per invalid value (empty when valid).
function CommunityRewardConfigModule.validate(config: CommunityRewardConfig): { string }
    local problems: { string } = {}
    local cooldown = config.recheckCooldownSeconds
    if not RewardConfig.isFinite(cooldown) or cooldown <= 0 then
        table.insert(problems, "communityReward.recheckCooldownSeconds must be positive")
    end
    if not config.enabled then
        return problems
    end
    local communityId = config.communityId
    if communityId == nil then
        table.insert(problems, "communityReward is enabled but has no communityId")
    elseif not RewardConfig.isPositiveInteger(communityId) then
        table.insert(problems, "communityReward.communityId must be a positive integer")
    end
    local reward = config.reward
    if reward == nil then
        table.insert(problems, "communityReward is enabled but has no reward")
    else
        for _, problem in RewardConfig.problems(reward, "communityReward.reward") do
            table.insert(problems, problem)
        end
    end
    return problems
end

return CommunityRewardConfigModule
