--!strict
--[[
    Port: redeem a promo code for a player. In-house implementation: features/codes/Codes.
    A paid pack plugs in as a second implementation of this port (ADR 0022).
]]

export type RedeemError =
    "cooldown"
    | "invalid_code"
    | "expired"
    | "already_redeemed"
    | "no_data"
    | "grant_failed"

export type Redeemed = { code: string, amount: number }

export type RedeemResult = { ok: true, value: Redeemed } | { ok: false, error: RedeemError }

export type Codes = {
    redeem: (self: Codes, userId: number, text: string) -> RedeemResult,
    -- Drops the per-player attempt state (call on PlayerRemoving).
    forget: (self: Codes, userId: number) -> (),
}

return {}
