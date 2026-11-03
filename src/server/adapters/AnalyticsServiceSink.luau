--!strict
--[[
    Adapter: AnalyticsSink over AnalyticsService:LogCustomEvent (server-only, published games
    only, at most 100 custom events per game, aggregated daily). Engine-only: not testable
    under Lune. Event names are validated before they reach this sink (AnalyticsTracker).
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnalyticsSinkPort = require(ReplicatedStorage.Shared.ports.AnalyticsSink)

local AnalyticsServiceSink = {}

function AnalyticsServiceSink.new(): AnalyticsSinkPort.AnalyticsSink
    local sink: AnalyticsSinkPort.AnalyticsSink = {
        log = function(
            _self: AnalyticsSinkPort.AnalyticsSink,
            event: AnalyticsSinkPort.FunnelEvent
        )
            local player = Players:GetPlayerByUserId(event.userId)
            if player == nil then
                return -- The player left before the event was sent; drop it.
            end
            AnalyticsService:LogCustomEvent(player, event.name, event.sessionIndex)
        end,
    }
    return sink
end

return AnalyticsServiceSink
