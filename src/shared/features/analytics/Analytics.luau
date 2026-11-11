--!strict
--[[
    Funnel event names and a pure event builder. Pure: loads under Lune.
    Sending the event (AnalyticsService, own backend) is the caller's job.
]]

export type FunnelEventName =
    "session_start"
    | "tutorial_start"
    | "tutorial_complete"
    | "first_action"
    | "first_purchase_prompt"
    | "first_purchase"
    | "day1_return"
    | "session_5min"
    | "session_end"

export type FunnelEvent = {
    name: FunnelEventName,
    userId: number,
    timestamp: number,
    sessionIndex: number,
    -- "<experimentId>:<variantId>" of the funnel experiment, when one is running.
    variant: string?,
}

local Analytics = {}

--- Seconds into a session when `session_5min` fires (the 5-minute retention mark).
Analytics.SESSION_MARK_SECONDS = 300

--- Every valid funnel event, in funnel order.
Analytics.eventNames = {
    "session_start",
    "tutorial_start",
    "tutorial_complete",
    "first_action",
    "first_purchase_prompt",
    "first_purchase",
    "day1_return",
    "session_5min",
    "session_end",
} :: { FunnelEventName }

function Analytics.isFunnelEvent(name: string): boolean
    for _, candidate in Analytics.eventNames do
        if candidate == name then
            return true
        end
    end
    return false
end

function Analytics.buildEvent(
    name: FunnelEventName,
    userId: number,
    timestamp: number,
    sessionIndex: number,
    variant: string?
): FunnelEvent
    return {
        name = name,
        userId = userId,
        timestamp = timestamp,
        sessionIndex = sessionIndex,
        variant = variant,
    }
end

--- Position of an event in the funnel (1-based), or nil when unknown.
function Analytics.funnelStep(name: FunnelEventName): number?
    for index, candidate in Analytics.eventNames do
        if candidate == name then
            return index
        end
    end
    return nil
end

return Analytics
