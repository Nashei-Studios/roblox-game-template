--!strict
--[[
    Port: daily streak reward and session gifts. In-house implementation:
    features/timerewards/TimeRewards. Server clock only.
]]

export type ClaimError =
    "no_data"
    | "already_claimed"
    | "clock_regressed"
    | "unknown_gift"
    | "not_ready"
    | "no_session"
    | "grant_failed"

export type Claimed = { amount: number, streak: number? }

export type ClaimResult = { ok: true, value: Claimed } | { ok: false, error: ClaimError }

export type TimeRewards = {
    -- Records when the player's session started (call on join).
    startSession: (self: TimeRewards, userId: number) -> (),
    claimDaily: (self: TimeRewards, userId: number) -> ClaimResult,
    claimSession: (self: TimeRewards, userId: number, giftId: string) -> ClaimResult,
    -- Drops the per-player session state (call on PlayerRemoving).
    forget: (self: TimeRewards, userId: number) -> (),
}

return {}
