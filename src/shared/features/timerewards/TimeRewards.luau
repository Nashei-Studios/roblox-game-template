--!strict
--[[
    Daily streak reward and session gifts (issue #27). Implements ports/TimeRewards. Pure: loads
    under Lune; the SERVER clock and the player data are injected.

    - Daily: idempotent per UTC day (the profile stores the last claimed day and the streak).
    - Session gifts: idempotent per session (claimed set kept in memory, cleared on `forget`).
    - Rewards go through the existing grant path (ProductGrants, keyed `daily:<day>` and
      `session:<id>`); state is written only after the grant succeeded, in the same step.
]]

local ProductGrants = require("../monetization/ProductGrants")
local SessionGifts = require("./SessionGifts")
local StreakClock = require("./StreakClock")
local TimeRewardsConfig = require("./TimeRewardsConfig")

type ClaimError =
    "no_data"
    | "already_claimed"
    | "clock_regressed"
    | "unknown_gift"
    | "not_ready"
    | "no_session"
    | "grant_failed"
type Claimed = { amount: number, streak: number? }
type ClaimResult = { ok: true, value: Claimed } | { ok: false, error: ClaimError }

export type TimeRewards = {
    startSession: (self: TimeRewards, userId: number) -> (),
    claimDaily: (self: TimeRewards, userId: number) -> ClaimResult,
    claimSession: (self: TimeRewards, userId: number, giftId: string) -> ClaimResult,
    forget: (self: TimeRewards, userId: number) -> (),
}

-- The slice of PlayerData that time rewards read and write.
export type TimeProfile = {
    coins: number,
    timeRewards: StreakClock.State,
}

export type Deps = {
    config: TimeRewardsConfig.TimeRewardsConfig,
    -- Server clock, Unix seconds (os.time in production).
    now: () -> number,
    profileFor: (userId: number) -> TimeProfile?,
    -- Built from `TimeRewardsModule.grantTable(config)`.
    grants: ProductGrants.ProductGrants,
}

type SessionState = { joinedAt: number, claimed: { [string]: boolean } }

local TimeRewardsModule = {}

--- Grant declarations keyed `daily:<day>` / `session:<id>`: the input of ProductGrants.new.
function TimeRewardsModule.grantTable(
    config: TimeRewardsConfig.TimeRewardsConfig
): { [string]: ProductGrants.ProductGrant }
    local grants: { [string]: ProductGrants.ProductGrant } = {}
    for _, entry in config.daily do
        grants[`daily:{entry.day}`] = entry.reward
    end
    for _, gift in config.sessionGifts do
        grants[`session:{gift.id}`] = gift.reward
    end
    return grants
end

function TimeRewardsModule.new(deps: Deps): TimeRewards
    local sessions: { [number]: SessionState } = {}

    local service: TimeRewards = {
        startSession = function(_self: TimeRewards, userId: number)
            sessions[userId] = { joinedAt = deps.now(), claimed = {} }
        end,
        claimDaily = function(_self: TimeRewards, userId: number): ClaimResult
            local profile = deps.profileFor(userId)
            if profile == nil then
                return { ok = false, error = "no_data" }
            end
            local now = deps.now()
            local state = profile.timeRewards
            local decision = StreakClock.evaluate(state, now, deps.config.graceHours)
            if not decision.ok then
                return { ok = false, error = decision.reason }
            end
            local cycle = #deps.config.daily
            local entry = deps.config.daily[((decision.streak - 1) % cycle) + 1]
            local applied = deps.grants:apply(profile, `daily:{entry.day}`)
            if not applied.ok then
                return { ok = false, error = "grant_failed" }
            end
            state.lastDay = decision.day
            state.streak = decision.streak
            return { ok = true, value = { amount = entry.reward.amount, streak = decision.streak } }
        end,
        claimSession = function(_self: TimeRewards, userId: number, giftId: string): ClaimResult
            local profile = deps.profileFor(userId)
            if profile == nil then
                return { ok = false, error = "no_data" }
            end
            local session = sessions[userId]
            if session == nil then
                return { ok = false, error = "no_session" }
            end
            local checked =
                SessionGifts.check(deps.config.sessionGifts, giftId, session.joinedAt, deps.now(), session.claimed)
            if not checked.ok then
                return { ok = false, error = checked.reason }
            end
            local applied = deps.grants:apply(profile, `session:{giftId}`)
            if not applied.ok then
                return { ok = false, error = "grant_failed" }
            end
            session.claimed[giftId] = true
            return { ok = true, value = { amount = checked.gift.reward.amount, streak = nil } }
        end,
        forget = function(_self: TimeRewards, userId: number)
            sessions[userId] = nil
        end,
    }
    return service
end

return TimeRewardsModule
