--!strict
--[[
    Server handler for the RequestRewardedAd remote (ADR 0012, ADR 0022). Pure: loads under Lune.
    The remote carries INTENT only ("play the ad for placement X", sent when the player presses
    the opt-in button). Order of checks: enabled flag, rate limiter, `Validation`, daily cap,
    then the AdGateway.

    Rules (docs: production/promotion/rewarded-video-ads):
    - Opt-in and off by default: `rewardedAds.enabled` is false until the experience is eligible.
    - This module NEVER grants. A completed ad earns the Config developer product through the
      Monetization receipt path, after a confirmed save (ADR 0016); a client or gateway
      "completed" signal is only used to count the daily cap.
    - Every unavailable or ineligible result is a normal outcome, not an error: the caller hides
      the button and shows nothing.
    - No progress gating: nothing here reads or blocks game progress.
]]

local AdGateway = require("../../ports/AdGateway")
local Config = require("../../Config")
local Validation = require("../../net/Validation")

export type Rejection =
    "disabled"
    | "rate_limited"
    | "daily_cap_reached"
    | "reward_not_configured"
    | "show_failed"
    | Validation.ValidationError

export type HandleResult =
    { ok: true, outcome: AdGateway.ShowOutcome }
    | { ok: false, reason: Rejection, detail: string? }

export type Deps = {
    config: Config.RewardedAdsConfig,
    -- Roblox id of a developer product by Config name; nil while the id is unset.
    productIdOf: (productName: string) -> number?,
    gateway: AdGateway.AdGateway,
    -- True when the player still has remote budget (RateLimiter.allow bound to this remote).
    allow: (userId: number) -> boolean,
    -- A number that changes once per UTC day (for example os.time() // 86400).
    dayKey: () -> number,
}

export type RewardedAds = {
    handle: (self: RewardedAds, userId: number, placement: unknown) -> HandleResult,
    -- Completed ads the player can still watch today (0 hides the button).
    remainingToday: (self: RewardedAds, userId: number) -> number,
    -- Disclosure text and per-placement button labels, all from Config.
    disclosure: (self: RewardedAds) -> string,
    labelOf: (self: RewardedAds, placement: string) -> string?,
    forget: (self: RewardedAds, userId: number) -> (),
}

type DailyCount = { day: number, completed: number }

local RewardedAdsModule = {}

function RewardedAdsModule.new(deps: Deps): RewardedAds
    local counts: { [number]: DailyCount } = {}

    local function countFor(userId: number): DailyCount
        local today = deps.dayKey()
        local count = counts[userId]
        if count == nil or count.day ~= today then
            count = { day = today, completed = 0 }
            counts[userId] = count
        end
        return count
    end

    local function placementNames(): { string }
        local names: { string } = {}
        for _, placement in deps.config.placements do
            table.insert(names, placement.name)
        end
        return names
    end

    local ads: RewardedAds
    ads = {
        handle = function(_self: RewardedAds, userId: number, placement: unknown): HandleResult
            if not deps.config.enabled then
                return { ok = false, reason = "disabled" }
            end
            if not deps.allow(userId) then
                return { ok = false, reason = "rate_limited" }
            end
            local checked = Validation.oneOf(placement, placementNames())
            if not checked.ok then
                return { ok = false, reason = checked.error }
            end
            if ads:remainingToday(userId) <= 0 then
                return { ok = false, reason = "daily_cap_reached" }
            end
            local rewardProductId: number? = nil
            for _, candidate in deps.config.placements do
                if candidate.name == checked.value then
                    rewardProductId = deps.productIdOf(candidate.rewardProduct)
                end
            end
            if rewardProductId == nil then
                return { ok = false, reason = "reward_not_configured" }
            end
            local placementId: number? = nil
            for _, candidate in deps.config.placements do
                if candidate.name == checked.value then
                    placementId = candidate.placementId
                end
            end
            local shown = deps.gateway:show(userId, {
                placementId = placementId,
                rewardProductId = rewardProductId,
            })
            if not shown.ok then
                return { ok = false, reason = "show_failed", detail = shown.error.message }
            end
            if shown.value == "completed" then
                countFor(userId).completed += 1
            end
            return { ok = true, outcome = shown.value }
        end,
        remainingToday = function(_self: RewardedAds, userId: number): number
            if not deps.config.enabled then
                return 0
            end
            return math.max(0, deps.config.dailyCap - countFor(userId).completed)
        end,
        disclosure = function(_self: RewardedAds): string
            return deps.config.disclosureLabel
        end,
        labelOf = function(_self: RewardedAds, placement: string): string?
            for _, candidate in deps.config.placements do
                if candidate.name == placement then
                    return candidate.label
                end
            end
            return nil
        end,
        forget = function(_self: RewardedAds, userId: number)
            counts[userId] = nil
        end,
    }
    return ads
end

return RewardedAdsModule
