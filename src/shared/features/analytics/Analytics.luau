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
    | "session_end"

export type FunnelEvent = {
    name: FunnelEventName,
    userId: number,
    timestamp: number,
    sessionIndex: number,
}

local Analytics = {}

--- Every valid funnel event, in funnel order.
Analytics.eventNames = {
    "session_start",
    "tutorial_start",
    "tutorial_complete",
    "first_action",
    "first_purchase_prompt",
    "first_purchase",
    "day1_return",
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
    sessionIndex: number
): FunnelEvent
    return {
        name = name,
        userId = userId,
        timestamp = timestamp,
        sessionIndex = sessionIndex,
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
