--!strict
--[[
    Server handler for the RequestCommunityCheck remote (ADR 0012) and the check on join.
    Pure: loads under Lune. Intent only: "check again". The rate limiter runs first; the outcome
    reaches the player as a toast through the Notifier port. Failures stay silent for the player
    (no error, only the join card) and are returned to the caller for logging.
]]

local CommunityReward = require("./CommunityReward")
local Notifier = require("../../ports/Notifier")

export type HandleResult =
    { ok: true, outcome: CommunityReward.Outcome }
    | {
        ok: false,
        reason: "rate_limited" | CommunityReward.CheckError,
    }

export type Deps = {
    reward: CommunityReward.CommunityReward,
    notifier: Notifier.Notifier,
    allow: (userId: number) -> boolean,
}

export type CommunityRewardRequests = {
    -- The client pressed "Check again".
    handle: (self: CommunityRewardRequests, userId: number) -> HandleResult,
    -- The server checks once when the player's data is loaded; not rate limited (server initiated).
    onJoin: (self: CommunityRewardRequests, userId: number) -> HandleResult,
}

local CommunityRewardRequestsModule = {}

function CommunityRewardRequestsModule.new(deps: Deps): CommunityRewardRequests
    local function run(userId: number): HandleResult
        local checked = deps.reward:check(userId)
        if not checked.ok then
            return { ok = false, reason = checked.error }
        end
        if checked.outcome == "granted" then
            deps.notifier:notify(userId, "community_reward_claimed", checked.amount)
        elseif checked.outcome == "not_member" then
            deps.notifier:notify(userId, "community_not_member", 0)
        end
        return { ok = true, outcome = checked.outcome }
    end

    local handler: CommunityRewardRequests = {
        handle = function(_self: CommunityRewardRequests, userId: number): HandleResult
            if not deps.allow(userId) then
                return { ok = false, reason = "rate_limited" }
            end
            return run(userId)
        end,
        onJoin = function(_self: CommunityRewardRequests, userId: number): HandleResult
            return run(userId)
        end,
    }
    return handler
end

return CommunityRewardRequestsModule
