--!strict
--[[
    One-time community join reward (issue #36). Pure: loads under Lune; the membership checker,
    the clock, the profile and the save confirmation are injected.

    Rules:
    - Membership is decided on the server only. A `false` (possibly stale) is "not a member yet".
    - Idempotent: `communityRewardClaimed` lives in the profile; once true, nothing is granted again,
      whatever the player does (leave, rejoin, ask again).
    - The grant is kept only after the save is confirmed (ADR 0016): if the save is not confirmed
      the coins and the flag are rolled back, so a later check can try again.
    - A player who left the community keeps the reward already given (the flag is never cleared).
    - Checks are rate-limited per player by `recheckCooldownSeconds`; one check runs at a time.
]]

local CommunityRewardConfig = require("./CommunityRewardConfig")
local MembershipChecker = require("../../ports/MembershipChecker")
local ProductGrants = require("../monetization/ProductGrants")

export type CheckError =
    "disabled"
    | "no_data"
    | "cooldown"
    | "busy"
    | "check_failed"
    | "grant_failed"
    | "save_failed"

export type Outcome = "granted" | "already_claimed" | "not_member"

export type CheckResult =
    { ok: true, outcome: Outcome, amount: number }
    | { ok: false, error: CheckError }

export type CommunityReward = {
    check: (self: CommunityReward, userId: number) -> CheckResult,
    -- Drops the per-player state (call on PlayerRemoving).
    forget: (self: CommunityReward, userId: number) -> (),
}

-- The slice of PlayerData this module reads and writes.
export type Profile = { coins: number, communityRewardClaimed: boolean }

export type Deps = {
    config: CommunityRewardConfig.CommunityRewardConfig,
    checker: MembershipChecker.MembershipChecker,
    -- Server clock in seconds (os.clock is enough: only differences are used).
    now: () -> number,
    profileFor: (userId: number) -> Profile?,
    -- Built from `CommunityRewardModule.grantTable(config)`.
    grants: ProductGrants.ProductGrants,
    -- True when the profile holding the grant is confirmed saved (PlayerDataService.confirmSaved).
    confirmSaved: (userId: number) -> boolean,
}

local GRANT_KEY = "community"

local CommunityRewardModule = {}

--- Grant declarations for ProductGrants.new; empty while no reward is configured.
function CommunityRewardModule.grantTable(
    config: CommunityRewardConfig.CommunityRewardConfig
): { [string]: ProductGrants.ProductGrant }
    local grants: { [string]: ProductGrants.ProductGrant } = {}
    if config.reward ~= nil then
        grants[GRANT_KEY] = config.reward
    end
    return grants
end

function CommunityRewardModule.new(deps: Deps): CommunityReward
    local lastCheck: { [number]: number } = {}
    local running: { [number]: boolean } = {}

    local function run(userId: number, profile: Profile): CheckResult
        local communityId = deps.config.communityId
        local reward = deps.config.reward
        if communityId == nil or reward == nil then
            return { ok = false, error = "disabled" }
        end
        local membership = deps.checker:isMember(userId, communityId)
        if not membership.ok then
            return { ok = false, error = "check_failed" }
        end
        if not membership.value then
            return { ok = true, outcome = "not_member", amount = 0 }
        end
        local applied = deps.grants:apply(profile, GRANT_KEY)
        if not applied.ok then
            return { ok = false, error = "grant_failed" }
        end
        profile.communityRewardClaimed = true
        if not deps.confirmSaved(userId) then
            profile.coins -= reward.amount
            profile.communityRewardClaimed = false
            return { ok = false, error = "save_failed" }
        end
        return { ok = true, outcome = "granted", amount = reward.amount }
    end

    local service: CommunityReward = {
        check = function(_self: CommunityReward, userId: number): CheckResult
            if not deps.config.enabled then
                return { ok = false, error = "disabled" }
            end
            local profile = deps.profileFor(userId)
            if profile == nil then
                return { ok = false, error = "no_data" }
            end
            if profile.communityRewardClaimed then
                return { ok = true, outcome = "already_claimed", amount = 0 }
            end
            if running[userId] then
                return { ok = false, error = "busy" }
            end
            local now = deps.now()
            local previous = lastCheck[userId]
            if previous ~= nil and now - previous < deps.config.recheckCooldownSeconds then
                return { ok = false, error = "cooldown" }
            end
            lastCheck[userId] = now
            running[userId] = true
            local result = run(userId, profile)
            running[userId] = nil
            return result
        end,
        forget = function(_self: CommunityReward, userId: number)
            lastCheck[userId] = nil
            running[userId] = nil
        end,
    }
    return service
end

return CommunityRewardModule
