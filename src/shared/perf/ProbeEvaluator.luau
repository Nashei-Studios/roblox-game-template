--!strict
--[[
    Pure half of the dev performance probe (ADR 0019): turns a window of samples into findings
    against the budget. The engine half (`src/server/dev/PerfProbe`) only collects samples.
]]

local PerfBudget = require("./PerfBudget")

export type Sample = {
    heartbeatMs: number,
    sendKbps: number,
    receiveKbps: number,
    memoryMb: number,
}

export type Finding = { metric: string, observed: number, limit: number }

local ProbeEvaluator = {}

local function mean(samples: { Sample }, pick: (Sample) -> number): number
    local sum = 0
    for _, sample in samples do
        sum += pick(sample)
    end
    return sum / #samples
end

--- Server memory ceiling in MB for the largest number of connected players seen.
function ProbeEvaluator.memoryLimitMb(runtime: PerfBudget.Runtime, peakPlayers: number): number
    local totalMib = runtime.memoryBaseMib + runtime.memoryPerPlayerMib * peakPlayers
    return totalMib * runtime.maxMemoryFraction
end

--- Compares the window means (memory: the latest sample) with the budget. Empty window: no findings.
function ProbeEvaluator.evaluate(
    samples: { Sample },
    playerCount: number,
    peakPlayers: number,
    runtime: PerfBudget.Runtime
): { Finding }
    local findings: { Finding } = {}
    if #samples == 0 then
        return findings
    end
    local players = math.max(playerCount, 1)
    local checks: { Finding } = {
        {
            metric = "heartbeatMs",
            observed = mean(samples, function(sample: Sample): number
                return sample.heartbeatMs
            end),
            limit = runtime.maxHeartbeatMs,
        },
        {
            metric = "sendKbps",
            observed = mean(samples, function(sample: Sample): number
                return sample.sendKbps
            end),
            limit = runtime.sendKbpsPerPlayer * players,
        },
        {
            metric = "receiveKbps",
            observed = mean(samples, function(sample: Sample): number
                return sample.receiveKbps
            end),
            limit = runtime.receiveKbpsPerPlayer * players,
        },
        {
            metric = "memoryMb",
            observed = samples[#samples].memoryMb,
            limit = ProbeEvaluator.memoryLimitMb(runtime, peakPlayers),
        },
    }
    for _, check in checks do
        if check.observed > check.limit then
            table.insert(findings, check)
        end
    end
    return findings
end

return ProbeEvaluator
