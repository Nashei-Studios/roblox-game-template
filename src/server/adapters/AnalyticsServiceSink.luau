--!strict
--[[
    Adapter: AnalyticsSink over AnalyticsService:LogCustomEvent (server-only, published games
    only, at most 100 custom events per game, aggregated daily). The engine services are
    injected (ADR 0009) so this file loads under Lune and is tested with fakes; the composition
    root passes the real ones. Event names are validated before they reach this sink
    (AnalyticsTracker).
]]

-- Structurally identical to ports/AnalyticsSink.luau (kept local so this file loads under Lune).
type FunnelEvent = {
    name: string,
    userId: number,
    timestamp: number,
    sessionIndex: number,
}

type AnalyticsSink = {
    log: (self: AnalyticsSink, event: FunnelEvent) -> (),
}

-- The slice of the engine that this adapter uses; `P` is the engine's Player type.
export type PlayersLike<P> = {
    GetPlayerByUserId: (self: unknown, userId: number) -> P?,
}

export type AnalyticsServiceLike<P> = {
    LogCustomEvent: (self: unknown, player: P, eventName: string, value: number) -> (),
}

export type Deps<P> = {
    analytics: AnalyticsServiceLike<P>,
    players: PlayersLike<P>,
}

local AnalyticsServiceSink = {}

function AnalyticsServiceSink.new<P>(deps: Deps<P>): AnalyticsSink
    local sink: AnalyticsSink = {
        log = function(_self: AnalyticsSink, event: FunnelEvent)
            local player = deps.players:GetPlayerByUserId(event.userId)
            if player == nil then
                return -- The player left before the event was sent; drop it.
            end
            deps.analytics:LogCustomEvent(player, event.name, event.sessionIndex)
        end,
    }
    return sink
end

return AnalyticsServiceSink
