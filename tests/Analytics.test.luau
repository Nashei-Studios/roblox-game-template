--!strict
local Analytics = require("../src/shared/Analytics")
local harness = require("./harness")

return function(suite: harness.Harness)
    suite:test("isFunnelEvent accepts known names and rejects others", function()
        harness.isTrue(Analytics.isFunnelEvent("first_purchase"), "known")
        harness.isFalse(Analytics.isFunnelEvent("rage_quit"), "unknown")
    end)

    suite:test("funnel steps follow declaration order", function()
        harness.equal(Analytics.funnelStep("session_start"), 1)
        harness.equal(Analytics.funnelStep("session_end"), #Analytics.eventNames)
    end)

    suite:test("buildEvent carries all fields", function()
        local event = Analytics.buildEvent("tutorial_start", 7, 1000, 2)
        harness.equal(event.name, "tutorial_start")
        harness.equal(event.userId, 7)
        harness.equal(event.timestamp, 1000)
        harness.equal(event.sessionIndex, 2)
    end)
end
