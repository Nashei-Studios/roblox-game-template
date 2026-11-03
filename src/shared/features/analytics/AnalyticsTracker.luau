--!strict
--[[
    Builds funnel events and hands them to an injected sink. Pure: loads under Lune.
    Unknown event names are rejected here, not at the sink.
]]

export type FunnelEvent = {
    name: string,
    userId: number,
    timestamp: number,
    sessionIndex: number,
}

export type Sink = {
    log: (self: Sink, event: FunnelEvent) -> (),
}

export type Deps = {
    sink: Sink,
    clock: () -> number,
    isValidEvent: (name: string) -> boolean,
}

export type AnalyticsTracker = {
    -- Returns false (and logs nothing) for an unknown event name.
    track: (self: AnalyticsTracker, name: string, userId: number, sessionIndex: number) -> boolean,
}

local AnalyticsTrackerModule = {}

function AnalyticsTrackerModule.new(deps: Deps): AnalyticsTracker
    local tracker: AnalyticsTracker = {
        track = function(
            _self: AnalyticsTracker,
            name: string,
            userId: number,
            sessionIndex: number
        ): boolean
            if not deps.isValidEvent(name) then
                return false
            end
            deps.sink:log({
                name = name,
                userId = userId,
                timestamp = deps.clock(),
                sessionIndex = sessionIndex,
            })
            return true
        end,
    }
    return tracker
end

return AnalyticsTrackerModule
