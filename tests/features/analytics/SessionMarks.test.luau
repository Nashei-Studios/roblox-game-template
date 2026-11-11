--!strict
local Analytics = require("../../../src/shared/features/analytics/Analytics")
local SessionMarks = require("../../../src/shared/features/analytics/SessionMarks")
local harness = require("../../harness")

type Fixture = {
    marks: SessionMarks.SessionMarks,
    tracked: { string },
    present: { [number]: boolean },
    fire: () -> (),
    delays: { number },
}

local function newFixture(): Fixture
    local tracked: { string } = {}
    local delays: { number } = {}
    local pending: { () -> () } = {}
    local present: { [number]: boolean } = { [1] = true }
    local marks = SessionMarks.new({
        tracker = {
            track = function(
                _self: SessionMarks.Tracker,
                name: string,
                userId: number,
                sessionIndex: number
            ): boolean
                table.insert(tracked, `{name}:{userId}:{sessionIndex}`)
                return true
            end,
        },
        delay = function(seconds: number, callback: () -> ())
            table.insert(delays, seconds)
            table.insert(pending, callback)
        end,
        isPresent = function(userId: number): boolean
            return present[userId] == true
        end,
    })
    return {
        marks = marks,
        tracked = tracked,
        present = present,
        delays = delays,
        fire = function()
            for _, callback in pending do
                callback()
            end
        end,
    }
end

return function(suite: harness.Harness)
    suite:test("fires session_5min once, after the configured seconds", function()
        local fx = newFixture()
        fx.marks:start(1, 4)
        fx.marks:start(1, 4) -- same session again: no second timer
        harness.equal(#fx.delays, 1, "one timer")
        harness.equal(fx.delays[1], Analytics.SESSION_MARK_SECONDS, "300 s")
        harness.equal(#fx.tracked, 0, "nothing before the delay")
        fx.fire()
        harness.equal(#fx.tracked, 1, "fired once")
        harness.equal(fx.tracked[1], "session_5min:1:4", "event")
    end)

    suite:test("a player who left before the mark does not fire it", function()
        local fx = newFixture()
        fx.marks:start(1, 1)
        fx.present[1] = false
        fx.fire()
        harness.equal(#fx.tracked, 0, "left")
    end)

    suite:test("forget cancels the old session and a rejoin arms a new one", function()
        local fx = newFixture()
        fx.marks:start(1, 1)
        fx.marks:forget(1)
        fx.marks:start(1, 2)
        fx.fire()
        harness.equal(#fx.tracked, 1, "only the new session fires")
        harness.equal(fx.tracked[1], "session_5min:1:2", "new session")
    end)

    suite:test("session_5min is a funnel event before session_end", function()
        harness.isTrue(Analytics.isFunnelEvent("session_5min"), "valid")
        local step = Analytics.funnelStep("session_5min")
        harness.isTrue(step ~= nil and step < #Analytics.eventNames, "before session_end")
    end)
end
