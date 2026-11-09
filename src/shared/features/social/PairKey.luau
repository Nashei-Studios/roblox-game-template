--!strict
--[[
    The identity of an unordered pair of players on a UTC day (ADR 0031). A value object: build it
    only with `PairKey.new`, which puts the smaller id first, so A+B and B+A are the same key and
    the day can never be swapped with an id.
]]

export type PairKey = {
    low: number,
    high: number,
    day: number,
    -- "invite:{day}:{low}:{high}", the key the ledger stores.
    key: string,
}

local PairKeyModule = {}

--- Canonical constructor. Order of the two ids does not matter.
function PairKeyModule.new(first: number, second: number, day: number): PairKey
    local low = math.min(first, second)
    local high = math.max(first, second)
    return { low = low, high = high, day = day, key = `invite:{day}:{low}:{high}` }
end

return PairKeyModule
