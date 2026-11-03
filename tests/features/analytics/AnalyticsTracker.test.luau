--!strict
local Analytics = require("../../../src/shared/features/analytics/Analytics")
local AnalyticsTracker = require("../../../src/shared/features/analytics/AnalyticsTracker")
local harness = require("../../harness")

local function newTracker(received: { AnalyticsTracker.FunnelEvent })
    return AnalyticsTracker.new({
        sink = {
            log = function(_self: AnalyticsTracker.Sink, event: AnalyticsTracker.FunnelEvent)
                table.insert(received, event)
            end,
        },
        clock = function(): number
            return 1234
        end,
        isValidEvent = Analytics.isFunnelEvent,
    })
end

return function(suite: harness.Harness)
    suite:test("a valid event reaches the sink with the injected timestamp", function()
        local received: { AnalyticsTracker.FunnelEvent } = {}
        local tracker = newTracker(received)
        harness.isTrue(tracker:track("session_start", 5, 2), "accepted")
        harness.equal(#received, 1, "events")
        harness.equal(received[1].timestamp, 1234, "timestamp")
        harness.equal(received[1].userId, 5, "userId")
        harness.equal(received[1].sessionIndex, 2, "sessionIndex")
    end)

    suite:test("an unknown event is rejected and never logged", function()
        local received: { AnalyticsTracker.FunnelEvent } = {}
        local tracker = newTracker(received)
        harness.isFalse(tracker:track("made_up_event", 5, 1), "rejected")
        harness.equal(#received, 0, "events")
    end)
end
