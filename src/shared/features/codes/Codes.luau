--!strict
--[[
    Promo codes (issue #28). Implements ports/Codes. Pure: loads under Lune; the clock and the
    player data are injected.

    Rules:
    - Case-insensitive: text is trimmed and upper-cased before lookup.
    - A code has an optional expiry (server clock) and a per-player use limit; the count is
      stored in the profile (`redeemedCodes`), so it survives rejoin and server hops.
    - Attempts are throttled per player: `attemptCooldownSeconds` between attempts, doubled after
      `failureThreshold` consecutive failures (behaviour learned from the free RBLX Codes pack).
    - The reward goes through the existing grant path (ProductGrants, keyed by normalized code)
      and the use is recorded in the same synchronous step, so a reward is never given twice.
]]

local CodesConfig = require("./CodesConfig")
local ProductGrants = require("../monetization/ProductGrants")

-- Structurally identical to ports/Codes (kept local: this module is the implementation).
type RedeemError =
    "cooldown"
    | "invalid_code"
    | "expired"
    | "already_redeemed"
    | "no_data"
    | "grant_failed"
type Redeemed = { code: string, amount: number }
type RedeemResult = { ok: true, value: Redeemed } | { ok: false, error: RedeemError }

export type Codes = {
    redeem: (self: Codes, userId: number, text: string) -> RedeemResult,
    forget: (self: Codes, userId: number) -> (),
}

-- The slice of PlayerData that codes read and write.
export type CodesProfile = {
    coins: number,
    redeemedCodes: { [string]: number },
}

export type Deps = {
    config: CodesConfig.CodesConfig,
    -- Server clock, Unix seconds (os.time in production).
    now: () -> number,
    -- nil when the player's data is not loaded.
    profileFor: (userId: number) -> CodesProfile?,
    -- Built from `CodesModule.grantTable(config)`.
    grants: ProductGrants.ProductGrants,
}

type AttemptState = { nextAllowedAt: number, failures: number }

local CodesModule = {}

--- Grant declarations keyed by normalized code: the input of ProductGrants.new.
function CodesModule.grantTable(
    config: CodesConfig.CodesConfig
): { [string]: ProductGrants.ProductGrant }
    local table_: { [string]: ProductGrants.ProductGrant } = {}
    for _, entry in config.entries do
        table_[CodesConfig.normalize(entry.code)] = entry.reward
    end
    return table_
end

function CodesModule.new(deps: Deps): Codes
    local entries: { [string]: CodesConfig.CodeEntry } = {}
    for _, entry in deps.config.entries do
        entries[CodesConfig.normalize(entry.code)] = entry
    end
    local attempts: { [number]: AttemptState } = {}
    local cooldown = deps.config.attemptCooldownSeconds

    local function fail(state: AttemptState, now: number, error: RedeemError): RedeemResult
        state.failures += 1
        local wait = cooldown
        if state.failures >= deps.config.failureThreshold then
            wait = cooldown * 2
        end
        state.nextAllowedAt = now + wait
        return { ok = false, error = error }
    end

    local service: Codes = {
        redeem = function(_self: Codes, userId: number, text: string): RedeemResult
            local now = deps.now()
            local state = attempts[userId]
            if state == nil then
                state = { nextAllowedAt = 0, failures = 0 }
                attempts[userId] = state
            end
            if now < state.nextAllowedAt then
                return { ok = false, error = "cooldown" }
            end
            local profile = deps.profileFor(userId)
            if profile == nil then
                return { ok = false, error = "no_data" }
            end
            local key = CodesConfig.normalize(text)
            local entry = entries[key]
            if entry == nil then
                return fail(state, now, "invalid_code")
            end
            local expiresAt = entry.expiresAt
            if expiresAt ~= nil and now >= expiresAt then
                return fail(state, now, "expired")
            end
            local used = profile.redeemedCodes[key] or 0
            if used >= (entry.maxRedemptions or 1) then
                return fail(state, now, "already_redeemed")
            end
            local applied = deps.grants:apply(profile, key)
            if not applied.ok then
                return fail(state, now, "grant_failed")
            end
            profile.redeemedCodes[key] = used + 1
            state.failures = 0
            state.nextAllowedAt = now + cooldown
            return { ok = true, value = { code = key, amount = entry.reward.amount } }
        end,
        forget = function(_self: Codes, userId: number)
            attempts[userId] = nil
        end,
    }
    return service
end

return CodesModule
