--!strict
--[[
    Dev-only performance probe (ADR 0019). Every few seconds it samples server Heartbeat time,
    Stats network rates and memory, and warns when the mean breaks the budget in
    `shared/perf/PerfBudget`. The comparison is pure (`shared/perf/ProbeEvaluator`, tested);
    this file is engine code and is excluded from the coverage gate like the rest of the engine
    layer. It does nothing unless `Config.default.perfProbeEnabled` is true AND the server runs
    inside Studio, so production never starts it. Studio-only: Stats values are read locally and
    no Roblox web API is called.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local PerfBudget = require(game:GetService("ReplicatedStorage").Shared.perf.PerfBudget)
local ProbeEvaluator = require(game:GetService("ReplicatedStorage").Shared.perf.ProbeEvaluator)

local SAMPLE_INTERVAL_SECONDS = 1
local WINDOW_SIZE = 10

local PerfProbe = {}

--- Starts sampling when `enabled` and running in Studio. Returns whether it started.
function PerfProbe.start(enabled: boolean): boolean
    if not enabled or not RunService:IsStudio() then
        return false
    end
    local window: { ProbeEvaluator.Sample } = {}
    local peakPlayers = 0
    task.spawn(function()
        while true do
            task.wait(SAMPLE_INTERVAL_SECONDS)
            local playerCount = #Players:GetPlayers()
            peakPlayers = math.max(peakPlayers, playerCount)
            table.insert(window, {
                -- Stats.HeartbeatTime is in seconds.
                heartbeatMs = Stats.HeartbeatTime * 1000,
                sendKbps = Stats.DataSendKbps,
                receiveKbps = Stats.DataReceiveKbps,
                memoryMb = Stats:GetTotalMemoryUsageMb(),
            })
            if #window >= WINDOW_SIZE then
                local findings =
                    ProbeEvaluator.evaluate(window, playerCount, peakPlayers, PerfBudget.runtime)
                for _, finding in findings do
                    warn(
                        `[PerfProbe] {finding.metric} {finding.observed} is over the budget of {finding.limit}`
                    )
                end
                table.clear(window)
            end
        end
    end)
    return true
end

return PerfProbe
