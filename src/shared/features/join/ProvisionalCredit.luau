--!strict
--[[
    Server side of the provisional tap batch (ADR 0032). Pure: loads under Lune.

    A client may tap before MineHello arrives (the world is playable from frame 1). Those taps come
    as ONE batch per session, and the rules keep a modified client from cashing in a long wait:

    - Both ends of the window are SERVER clock readings: PlayerAdded (`begin`) and the moment the
      hello went out (`markHello`). The window freezes at the hello; waiting longer buys nothing.
    - The cap is `maxPerSecond * (helloAt - joinAt)`, the most a real player could have tapped.
    - A batch before the hello, or after the batch was consumed, is refused.
    - claim / commit: `claim` reserves the batch, the caller credits it, `commit` consumes it with
      what was really credited; `abort` gives the reservation back if crediting failed outright.
    The credit itself goes through the usual swing path, reach check included.
]]

export type Deps = {
    clock: () -> number,
    maxPerSecond: number,
}

export type Stats = { claimed: number, credited: number, consumed: boolean }

export type ProvisionalCredit = {
    begin: (self: ProvisionalCredit, userId: number) -> (),
    -- The hello went out now (server clock). Only the first call counts; it freezes the window.
    markHello: (self: ProvisionalCredit, userId: number) -> (),
    -- Reserves the batch and returns how many of `claimed` taps to credit (at most the frozen cap,
    -- possibly 0). nil: refused (no hello yet, already reserved or consumed, junk). A reserved
    -- batch must be committed or aborted.
    claim: (self: ProvisionalCredit, userId: number, claimed: number) -> number?,
    -- Consumes the batch for good with the taps really credited.
    commit: (self: ProvisionalCredit, userId: number, credited: number) -> (),
    -- Gives the reservation back (crediting failed before it applied anything).
    abort: (self: ProvisionalCredit, userId: number) -> (),
    stats: (self: ProvisionalCredit, userId: number) -> Stats?,
    forget: (self: ProvisionalCredit, userId: number) -> (),
}

type Entry = {
    joinAt: number,
    helloAt: number?,
    reserved: boolean,
    consumed: boolean,
    claimed: number,
    credited: number,
}

local ProvisionalCreditModule = {}

function ProvisionalCreditModule.new(deps: Deps): ProvisionalCredit
    local entries: { [number]: Entry } = {}
    local credit: ProvisionalCredit = {
        begin = function(_self: ProvisionalCredit, userId: number)
            entries[userId] = {
                joinAt = deps.clock(),
                reserved = false,
                consumed = false,
                claimed = 0,
                credited = 0,
            }
        end,
        markHello = function(_self: ProvisionalCredit, userId: number)
            local entry = entries[userId]
            if entry ~= nil and entry.helloAt == nil then
                entry.helloAt = deps.clock()
            end
        end,
        claim = function(_self: ProvisionalCredit, userId: number, claimed: number): number?
            local entry = entries[userId]
            if entry == nil or entry.reserved or entry.consumed then
                return nil
            end
            local helloAt = entry.helloAt
            if helloAt == nil or claimed ~= claimed or claimed < 1 then
                return nil
            end
            local cap = math.floor(deps.maxPerSecond * math.max(0, helloAt - entry.joinAt))
            entry.reserved = true
            entry.claimed = math.floor(claimed)
            return math.min(math.floor(claimed), cap)
        end,
        commit = function(_self: ProvisionalCredit, userId: number, credited: number)
            local entry = entries[userId]
            if entry ~= nil and entry.reserved then
                entry.reserved = false
                entry.consumed = true
                entry.credited = math.max(0, credited)
            end
        end,
        abort = function(_self: ProvisionalCredit, userId: number)
            local entry = entries[userId]
            if entry ~= nil and entry.reserved then
                entry.reserved = false
                entry.claimed = 0
            end
        end,
        stats = function(_self: ProvisionalCredit, userId: number): Stats?
            local entry = entries[userId]
            if entry == nil then
                return nil
            end
            return {
                claimed = entry.claimed,
                credited = entry.credited,
                consumed = entry.consumed,
            }
        end,
        forget = function(_self: ProvisionalCredit, userId: number)
            entries[userId] = nil
        end,
    }
    return credit
end

return ProvisionalCreditModule
