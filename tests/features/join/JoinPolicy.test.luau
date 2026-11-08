--!strict
local JoinPolicy = require("../../../src/shared/features/join/JoinPolicy")
local harness = require("../../harness")

return function(suite: harness.Harness)
    suite:test("the wait says stop when the player has left", function()
        local gone = false
        local wait = JoinPolicy.newWait({
            clock = function(): number
                return 0
            end,
            isGone = function(): boolean
                return gone
            end,
        })
        harness.isFalse(wait.cancel(), "still here")
        gone = true
        harness.isTrue(wait.cancel(), "left")
        harness.isFalse(wait.timedOut(), "leaving is not a timeout")
    end)

    suite:test("our own policy cancels the wait at 90 s", function()
        local now = 1000
        local wait = JoinPolicy.newWait({
            clock = function(): number
                return now
            end,
            isGone = function(): boolean
                return false
            end,
        })
        now = 1000 + JoinPolicy.MAX_WAIT_SECONDS - 0.5
        harness.isFalse(wait.cancel(), "just under the limit")
        harness.isFalse(wait.timedOut(), "not timed out yet")
        now = 1000 + JoinPolicy.MAX_WAIT_SECONDS
        harness.isTrue(wait.cancel(), "at the limit")
        harness.isTrue(wait.timedOut(), "timed out")
        harness.equal(JoinPolicy.MAX_WAIT_SECONDS, 90, "the policy is 90 s")
    end)

    suite:test("timedOut is read from the injected clock, not from a retry count", function()
        local now = 0
        local gone = false
        local wait = JoinPolicy.newWait({
            clock = function(): number
                return now
            end,
            isGone = function(): boolean
                return gone
            end,
            maxWaitSeconds = 10,
        })
        harness.isFalse(wait.timedOut(), "fresh")
        now = 9.9
        harness.isFalse(wait.timedOut(), "under the limit, however many times cancel was polled")
        for _ = 1, 50 do
            wait.cancel()
        end
        harness.isFalse(wait.timedOut(), "polling does not change it")
        now = 10
        harness.isTrue(wait.timedOut(), "limit reached by the clock")
        gone = true
        harness.isFalse(wait.timedOut(), "a player who left did not time out")
    end)

    suite:test("session_unavailable has its own distinct message", function()
        local unavailable = JoinPolicy.kickMessage(false, "session_unavailable")
        harness.equal(unavailable, JoinPolicy.KICK_UNAVAILABLE, "own message")
        harness.isTrue(unavailable ~= JoinPolicy.KICK_FAILED, "not the generic one")
        harness.isTrue(unavailable ~= JoinPolicy.KICK_TIMED_OUT, "not the timeout one")
        harness.equal(
            JoinPolicy.kickMessage(true, "session_unavailable"),
            JoinPolicy.KICK_TIMED_OUT,
            "timeout wins"
        )
        harness.equal(
            JoinPolicy.kickMessage(false, "save_failed"),
            JoinPolicy.KICK_FAILED,
            "others"
        )
    end)

    suite:test("the kick message says what happened", function()
        harness.equal(JoinPolicy.kickMessage(true), JoinPolicy.KICK_TIMED_OUT, "timeout")
        harness.equal(JoinPolicy.kickMessage(false), JoinPolicy.KICK_FAILED, "failure")
        harness.isTrue(JoinPolicy.KICK_TIMED_OUT ~= JoinPolicy.KICK_FAILED, "distinct")
    end)

    suite:test("guard returns true and calls nothing when the join works", function()
        local failures = 0
        local ok = JoinPolicy.guard(function() end, function(_message: string)
            failures += 1
        end)
        harness.isTrue(ok, "ok")
        harness.equal(failures, 0, "no failure callback")
    end)

    suite:test("guard never throws: an error becomes a failure callback", function()
        local captured = ""
        local ok = JoinPolicy.guard(function()
            error("boom")
        end, function(message: string)
            captured = message
        end)
        harness.isFalse(ok, "reported as failed")
        harness.isTrue(string.find(captured, "boom", 1, true) ~= nil, "message kept")
    end)

    suite:test("guard survives a failure callback that throws too", function()
        local reported = ""
        local ok = JoinPolicy.guard(function()
            error("first")
        end, function(_message: string)
            error("second")
        end, function(message: string)
            reported = message
        end)
        harness.isFalse(ok, "reported as failed, not thrown")
        harness.isTrue(string.find(reported, "second", 1, true) ~= nil, "handler error surfaced")
        harness.isTrue(string.find(reported, "first", 1, true) ~= nil, "original kept")
    end)
end
