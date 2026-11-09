--!strict
--[[
    Invite reward (ADR 0030): when a player joins through a referral, both the inviter and the
    invitee get the invite boost. Pure: loads under Lune; every effect is injected.

    Policy: the official referral-system page shows granting rewards to both the inviter and the
    invitee with `ReferredByPlayerId`, and the invite-prompts page states no restriction on
    in-experience rewards (read 2026-11-07, creator-docs). The reward is still behind the
    `inviteReward` flag so it can be switched off without a release. No Robux is involved.

    Rules:
    - Flag off: nothing happens and nothing is recorded.
    - Not self; the inviter must be present in the server (`isPresent`), otherwise nobody is paid.
    - Once per UNORDERED pair per UTC day (`PairKey`: A+B and B+A are the same), across servers
      (the shipped ledger is MemoryStore, ADR 0031), and at most `dailyPaidPerInviter` paid
      invites per inviter per day. Repeating a join is a no-op, so the grant is idempotent.
    - A ledger that cannot answer means no reward, never an error.
]]

local PairKey = require("./PairKey")
local Referral = require("./Referral")

export type Outcome =
    "granted"
    | "disabled"
    | "not_a_referral"
    | "self_referral"
    | "unknown_inviter"
    | "already_granted_today"
    | "inviter_daily_cap"

-- Both calls return true only when they won; a ledger that fails returns false and never throws.
export type Ledger = {
    -- Records the pair for its day. True only the first time.
    claimPair: (self: Ledger, pair: PairKey.PairKey) -> boolean,
    -- Takes one of the inviter's paid invites of the day. False once the daily cap is used.
    takeInviterSlot: (self: Ledger, inviterId: number, day: number) -> boolean,
}

export type Deps = {
    enabled: () -> boolean,
    -- Unix seconds.
    now: () -> number,
    isPresent: (userId: number) -> boolean,
    ledger: Ledger,
    -- Starts the invite boost for a player.
    grant: (userId: number) -> (),
    decode: (text: string) -> unknown,
}

export type InviteReward = {
    onJoin: (self: InviteReward, inviteeId: number, joinData: unknown) -> Outcome,
}

local SECONDS_PER_DAY = 86400

local InviteRewardModule = {}

--- A ledger kept in memory, for tests and as a fallback: one server only, so it does not stop
--- cross-server abuse (use HashMapLedger in production).
function InviteRewardModule.memoryLedger(dailyCap: number): Ledger
    local pairs: { [string]: boolean } = {}
    local slots: { [string]: number } = {}
    local ledger: Ledger = {
        claimPair = function(_self: Ledger, pair: PairKey.PairKey): boolean
            if pairs[pair.key] then
                return false
            end
            pairs[pair.key] = true
            return true
        end,
        takeInviterSlot = function(_self: Ledger, inviterId: number, day: number): boolean
            local key = `{day}:{inviterId}`
            local used = slots[key] or 0
            if used >= dailyCap then
                return false
            end
            slots[key] = used + 1
            return true
        end,
    }
    return ledger
end

function InviteRewardModule.new(deps: Deps): InviteReward
    local service: InviteReward = {
        onJoin = function(_self: InviteReward, inviteeId: number, joinData: unknown): Outcome
            if not deps.enabled() then
                return "disabled"
            end
            local inviterId = Referral.inviterOf(joinData, deps.decode)
            if inviterId == nil then
                return "not_a_referral"
            end
            if inviterId == inviteeId then
                return "self_referral"
            end
            if not deps.isPresent(inviterId) then
                return "unknown_inviter"
            end
            local day = math.floor(deps.now() / SECONDS_PER_DAY)
            if not deps.ledger:claimPair(PairKey.new(inviterId, inviteeId, day)) then
                return "already_granted_today"
            end
            if not deps.ledger:takeInviterSlot(inviterId, day) then
                return "inviter_daily_cap"
            end
            deps.grant(inviterId)
            deps.grant(inviteeId)
            return "granted"
        end,
    }
    return service
end

return InviteRewardModule
