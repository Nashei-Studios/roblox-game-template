--!strict
--[[
    Growth timers on the SERVER clock (ADR 0020). Pure: `now` is read from the injected Clock
    by the caller. A plot stores an absolute `readyAt`, so growth continues while the player is
    away. The client calls `remaining` only to draw a countdown; it never decides readiness.
]]

local GreenhouseData = require("./GreenhouseData")

export type PlotTimer = { cropId: string, readyAt: number }

local GrowthTimers = {}

--- Seconds until the plot is ready (0 when ready, empty or unknown crop). Clamped to the crop's
--- growSeconds, so a server clock that is behind the one that wrote `readyAt` cannot lock a
--- plot for longer than the crop allows.
function GrowthTimers.remaining(plot: PlotTimer, now: number): number
    local crop = GreenhouseData.cropById(plot.cropId)
    if crop == nil then
        return 0
    end
    return math.clamp(plot.readyAt - now, 0, crop.growSeconds)
end

function GrowthTimers.isEmpty(plot: PlotTimer): boolean
    return plot.cropId == ""
end

--- True when a crop is planted and its timer has run out on the server clock.
function GrowthTimers.isReady(plot: PlotTimer, now: number): boolean
    return GreenhouseData.cropById(plot.cropId) ~= nil and GrowthTimers.remaining(plot, now) <= 0
end

--- 0..1 of the growth that has elapsed (1 when ready, 0 when empty).
function GrowthTimers.progress(plot: PlotTimer, now: number): number
    local crop = GreenhouseData.cropById(plot.cropId)
    if crop == nil then
        return 0
    end
    return 1 - GrowthTimers.remaining(plot, now) / crop.growSeconds
end

return GrowthTimers
