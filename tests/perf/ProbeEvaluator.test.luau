--!strict
local PerfBudget = require("../../src/shared/perf/PerfBudget")
local ProbeEvaluator = require("../../src/shared/perf/ProbeEvaluator")
local harness = require("../harness")

local function sample(
    heartbeatMs: number,
    sendKbps: number,
    receiveKbps: number,
    memoryMb: number
): ProbeEvaluator.Sample
    return {
        heartbeatMs = heartbeatMs,
        sendKbps = sendKbps,
        receiveKbps = receiveKbps,
        memoryMb = memoryMb,
    }
end

return function(suite: harness.Harness)
    suite:test("memory limit follows the documented formula", function()
        local runtime = PerfBudget.runtime
        harness.equal(ProbeEvaluator.memoryLimitMb(runtime, 30), (6400 + 3000) * 0.5)
    end)

    suite:test("no findings for an empty window or a healthy one", function()
        harness.equal(#ProbeEvaluator.evaluate({}, 10, 10, PerfBudget.runtime), 0)
        local healthy = { sample(5, 1, 1, 1000), sample(7, 2, 1, 1100) }
        harness.equal(#ProbeEvaluator.evaluate(healthy, 10, 10, PerfBudget.runtime), 0)
    end)

    suite:test("reports every metric over its limit", function()
        local bad = { sample(20, 1000, 1000, 99999), sample(30, 1000, 1000, 99999) }
        local findings = ProbeEvaluator.evaluate(bad, 2, 2, PerfBudget.runtime)
        harness.equal(#findings, 4)
        harness.equal(findings[1].metric, "heartbeatMs")
        harness.equal(findings[1].observed, 25)
    end)

    suite:test("network limits scale with players and an empty server counts as one", function()
        local runtime = PerfBudget.runtime
        local window = { sample(1, runtime.sendKbpsPerPlayer * 5, 0, 1) }
        harness.equal(#ProbeEvaluator.evaluate(window, 5, 5, runtime), 0)
        harness.equal(#ProbeEvaluator.evaluate(window, 4, 5, runtime), 1)
        local idle = { sample(1, runtime.sendKbpsPerPlayer + 1, 0, 1) }
        harness.equal(#ProbeEvaluator.evaluate(idle, 0, 0, runtime), 1)
    end)
end
