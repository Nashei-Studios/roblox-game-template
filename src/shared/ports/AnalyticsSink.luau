--!strict
--[[
    Port: where funnel events go. Adapter: src/server/adapters/AnalyticsServiceSink.luau.
]]

export type FunnelEvent = {
    name: string,
    userId: number,
    timestamp: number,
    sessionIndex: number,
}

export type AnalyticsSink = {
    log: (self: AnalyticsSink, event: FunnelEvent) -> (),
}

return {}
