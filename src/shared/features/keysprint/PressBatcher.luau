--!strict
--[[
    Client-side press batching (pure, so it is tested under Lune). Key presses are counted and
    sent as one PressBatch per interval instead of one remote per press (ADR 0019 budget). The
    server does not trust the count; this only keeps the client inside the remote's rate and the
    batch size the server accepts.
]]

local KeySprintRules = require("./KeySprintRules")

export type PressBatcher = {
    press: (self: PressBatcher) -> (),
    -- Call every frame or tick with a monotonic time. Returns how many presses to send now
    -- (0 when the window is not over or nothing is waiting), at most MAX_PRESSES_PER_BATCH.
    flush: (self: PressBatcher, now: number) -> number,
}

local PressBatcherModule = {}

-- Presses held while waiting for the next window; a stuck key cannot grow this.
PressBatcherModule.MAX_PENDING = 60

function PressBatcherModule.new(intervalSeconds: number): PressBatcher
    local pending = 0
    local windowStart: number? = nil

    local batcher: PressBatcher = {
        press = function(_self: PressBatcher)
            pending = math.min(pending + 1, PressBatcherModule.MAX_PENDING)
        end,
        flush = function(_self: PressBatcher, now: number): number
            if windowStart == nil then
                windowStart = now
                return 0
            end
            if pending == 0 or now - windowStart < intervalSeconds then
                return 0
            end
            local count = math.min(pending, KeySprintRules.MAX_PRESSES_PER_BATCH)
            pending -= count
            windowStart = now
            return count
        end,
    }
    return batcher
end

return PressBatcherModule
