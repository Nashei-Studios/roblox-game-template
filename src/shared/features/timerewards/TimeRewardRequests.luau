--!strict
--[[
    Server handlers for the ClaimDailyReward and ClaimSessionGift remotes (ADR 0012, ADR 0015).
    Pure: loads under Lune. Intent only: "claim the daily" / "claim gift X". Rate limiter first,
    then Validation of the gift id against the configured ids, then the TimeRewards port; the
    outcome reaches the player as a toast through the Notifier port.
]]

local Notifier = require("../../ports/Notifier")
local TimeRewards = require("../../ports/TimeRewards")
local Validation = require("../../net/Validation")

export type Rejection = "rate_limited" | Validation.ValidationError | TimeRewards.ClaimError

export type HandleResult = { ok: true, amount: number } | { ok: false, reason: Rejection }

export type Deps = {
    timeRewards: TimeRewards.TimeRewards,
    notifier: Notifier.Notifier,
    allowDaily: (userId: number) -> boolean,
    allowSession: (userId: number) -> boolean,
    -- Ids of Config.default.timeRewards.sessionGifts.
    giftIds: { string },
}

export type TimeRewardRequests = {
    handleDaily: (self: TimeRewardRequests, userId: number) -> HandleResult,
    handleSession: (self: TimeRewardRequests, userId: number, giftId: unknown) -> HandleResult,
}

local TimeRewardRequestsModule = {}

function TimeRewardRequestsModule.new(deps: Deps): TimeRewardRequests
    local handler: TimeRewardRequests = {
        handleDaily = function(_self: TimeRewardRequests, userId: number): HandleResult
            if not deps.allowDaily(userId) then
                return { ok = false, reason = "rate_limited" }
            end
            local claimed = deps.timeRewards:claimDaily(userId)
            if not claimed.ok then
                deps.notifier:notify(userId, "daily_unavailable", 0)
                return { ok = false, reason = claimed.error }
            end
            deps.notifier:notify(userId, "daily_claimed", claimed.value.amount)
            return { ok = true, amount = claimed.value.amount }
        end,
        handleSession = function(
            _self: TimeRewardRequests,
            userId: number,
            giftId: unknown
        ): HandleResult
            if not deps.allowSession(userId) then
                return { ok = false, reason = "rate_limited" }
            end
            local checked = Validation.oneOf(giftId, deps.giftIds)
            if not checked.ok then
                return { ok = false, reason = checked.error }
            end
            local claimed = deps.timeRewards:claimSession(userId, checked.value)
            if not claimed.ok then
                deps.notifier:notify(userId, "session_gift_unavailable", 0)
                return { ok = false, reason = claimed.error }
            end
            deps.notifier:notify(userId, "session_gift_claimed", claimed.value.amount)
            return { ok = true, amount = claimed.value.amount }
        end,
    }
    return handler
end

return TimeRewardRequestsModule
