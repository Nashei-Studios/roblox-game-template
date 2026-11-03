--!strict
--[[
    Server handler for the RequestPurchase remote (ADR 0012, ADR 0015). Pure: loads under Lune.
    The remote carries INTENT only ("I want product X"). Order of checks: the rate limiter first
    (a flooded client costs one bucket lookup, nothing else), then `Validation`, then the
    injected `prompt`. The generated Zap layer already rejects values outside the schema enum;
    this module is the second, independent gate and the one that owns the policy.
]]

local Validation = require("../../net/Validation")

export type Rejection = "rate_limited" | "prompt_failed" | Validation.ValidationError

export type HandleResult = { ok: true, product: string } | { ok: false, reason: Rejection }

export type Deps = {
    -- Product names a player may request (from Config.developerProducts).
    productNames: { string },
    -- True when the player still has budget (RateLimiter.allow bound to the purchase limiter).
    allow: (userId: number) -> boolean,
    -- Opens the purchase prompt; false when it could not (unknown id, player gone).
    prompt: (userId: number, productName: string) -> boolean,
}

export type PurchaseRequests = {
    handle: (self: PurchaseRequests, userId: number, product: unknown) -> HandleResult,
}

local PurchaseRequestsModule = {}

function PurchaseRequestsModule.new(deps: Deps): PurchaseRequests
    local handler: PurchaseRequests = {
        handle = function(_self: PurchaseRequests, userId: number, product: unknown): HandleResult
            if not deps.allow(userId) then
                return { ok = false, reason = "rate_limited" }
            end
            local checked = Validation.oneOf(product, deps.productNames)
            if not checked.ok then
                return { ok = false, reason = checked.error }
            end
            if not deps.prompt(userId, checked.value) then
                return { ok = false, reason = "prompt_failed" }
            end
            return { ok = true, product = checked.value }
        end,
    }
    return handler
end

return PurchaseRequestsModule
