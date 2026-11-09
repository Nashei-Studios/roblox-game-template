--!strict
--[[
    When the client asks for the hello again (ADR 0032). Pure: loads under Lune.

    The hello can be missed (it was sent before the client's listener existed, or the first request
    came before the profile did). The client asks at 2 s, 5 s and 10 s after it started, then slowly
    and forever (every 15 s) until a hello arrives, so a slow join never leaves it hanging.
    `due` is polled every frame; it returns true at most once per scheduled moment.
]]

export type HelloRetry = {
    -- true when a request should be sent now: a moment has passed and no hello arrived.
    due: (self: HelloRetry, elapsedSeconds: number) -> boolean,
    -- The hello arrived: no more requests.
    received: (self: HelloRetry) -> (),
    -- How many requests were handed out.
    sent: (self: HelloRetry) -> number,
}

local HelloRetryModule = {}

HelloRetryModule.DELAYS = { 2, 5, 10 }
-- After the backoff, one request every this many seconds, until the hello arrives.
HelloRetryModule.SLOW_PERIOD_SECONDS = 15

function HelloRetryModule.new(delays: { number }?, slowPeriod: number?): HelloRetry
    local schedule = delays or HelloRetryModule.DELAYS
    local period = slowPeriod or HelloRetryModule.SLOW_PERIOD_SECONDS
    local nextIndex = 1
    local nextSlowAt = (schedule[#schedule] or 0) + period
    local requests = 0
    local done = false
    local retry: HelloRetry = {
        due = function(_self: HelloRetry, elapsedSeconds: number): boolean
            if done then
                return false
            end
            if nextIndex <= #schedule then
                if elapsedSeconds < schedule[nextIndex] then
                    return false
                end
                -- A long stall skips the moments it jumped over: one request, not a burst.
                while nextIndex <= #schedule and elapsedSeconds >= schedule[nextIndex] do
                    nextIndex += 1
                end
                while elapsedSeconds >= nextSlowAt do
                    nextSlowAt += period
                end
                requests += 1
                return true
            end
            if elapsedSeconds < nextSlowAt then
                return false
            end
            while elapsedSeconds >= nextSlowAt do
                nextSlowAt += period
            end
            requests += 1
            return true
        end,
        received = function(_self: HelloRetry)
            done = true
        end,
        sent = function(_self: HelloRetry): number
            return requests
        end,
    }
    return retry
end

return HelloRetryModule
