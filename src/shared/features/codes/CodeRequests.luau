--!strict
--[[
    Server handler for the RedeemCode remote (ADR 0012, ADR 0015). Pure: loads under Lune.
    The remote carries INTENT only (the text the player typed). Order: rate limiter first, then
    Validation (string, length), then the Codes port; the outcome reaches the player as a toast
    through the Notifier port. A rate-limited request gets no answer at all.
]]

local Codes = require("../../ports/Codes")
local Notifier = require("../../ports/Notifier")
local Validation = require("../../net/Validation")

export type Rejection = "rate_limited" | Validation.ValidationError | Codes.RedeemError

export type HandleResult = { ok: true, code: string } | { ok: false, reason: Rejection }

export type Deps = {
    codes: Codes.Codes,
    notifier: Notifier.Notifier,
    allow: (userId: number) -> boolean,
    -- Same value as Config.default.codes.maxCodeLength.
    maxCodeLength: number,
}

export type CodeRequests = {
    handle: (self: CodeRequests, userId: number, text: unknown) -> HandleResult,
}

local ERROR_KIND: { [string]: string } = {
    cooldown = "code_cooldown",
    invalid_code = "code_invalid",
    expired = "code_expired",
    already_redeemed = "code_used",
    no_data = "code_invalid",
    grant_failed = "code_invalid",
}

local CodeRequestsModule = {}

function CodeRequestsModule.new(deps: Deps): CodeRequests
    local handler: CodeRequests = {
        handle = function(_self: CodeRequests, userId: number, text: unknown): HandleResult
            if not deps.allow(userId) then
                return { ok = false, reason = "rate_limited" }
            end
            local checked = Validation.string(text, 1, deps.maxCodeLength)
            if not checked.ok then
                deps.notifier:notify(userId, "code_invalid", 0)
                return { ok = false, reason = checked.error }
            end
            local redeemed = deps.codes:redeem(userId, checked.value)
            if not redeemed.ok then
                deps.notifier:notify(userId, ERROR_KIND[redeemed.error], 0)
                return { ok = false, reason = redeemed.error }
            end
            deps.notifier:notify(userId, "code_redeemed", redeemed.value.amount)
            return { ok = true, code = redeemed.value.code }
        end,
    }
    return handler
end

return CodeRequestsModule
