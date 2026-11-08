--!strict
--[[
    The invite ledger on a MemoryStore hash map (ADR 0031). Pure: loads under Lune; the map is
    injected, so the real `MemoryStoreService:GetHashMap` is only touched in the server wiring.

    - claimPair: atomic. `UpdateAsync` runs the callback on the latest value; returning nil
      cancels the update, so a pair already stored is refused. Key "invite:{day}:{low}:{high}",
      unordered, expires after 24 h.
    - takeInviterSlot: a counter per inviter and day, refused once it reaches the daily cap.
    - Any failure of the store (throttling, outage, conflict) returns false: no reward, no error.
]]

local InviteReward = require("./InviteReward")
local PairKey = require("./PairKey")

-- The slice of MemoryStoreHashMap this ledger uses. `transform` returns the new value, or nil to
-- cancel; the call returns the stored value, or nil when it was cancelled.
export type HashMapLike = {
    UpdateAsync: (
        self: HashMapLike,
        key: string,
        transform: (old: unknown) -> unknown,
        expirationSeconds: number
    ) -> unknown,
}

local EXPIRATION_SECONDS = 24 * 60 * 60

local HashMapLedgerModule = {}

HashMapLedgerModule.EXPIRATION_SECONDS = EXPIRATION_SECONDS

function HashMapLedgerModule.new(map: HashMapLike, dailyCap: number): InviteReward.Ledger
    local ledger: InviteReward.Ledger = {
        claimPair = function(_self: InviteReward.Ledger, pair: PairKey.PairKey): boolean
            local called, stored = pcall(function()
                return map:UpdateAsync(pair.key, function(old: unknown): unknown
                    if old ~= nil then
                        return nil
                    end
                    return 1
                end, EXPIRATION_SECONDS)
            end)
            return called and stored ~= nil
        end,
        takeInviterSlot = function(
            _self: InviteReward.Ledger,
            inviterId: number,
            day: number
        ): boolean
            local called, stored = pcall(function()
                return map:UpdateAsync(
                    `invite-count:{day}:{inviterId}`,
                    function(old: unknown): unknown
                        local used = if type(old) == "number" then old else 0
                        if used >= dailyCap then
                            return nil
                        end
                        return used + 1
                    end,
                    EXPIRATION_SECONDS
                )
            end)
            return called and stored ~= nil
        end,
    }
    return ledger
end

return HashMapLedgerModule
