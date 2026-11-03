--!strict
local Funnel = require("../../../src/shared/features/keysprint/Funnel")
local harness = require("../../harness")

local function newFunnel()
    local sent: { string } = {}
    local funnel = Funnel.new({
        track = function(name: string, _userId: number, _sessionIndex: number): boolean
            table.insert(sent, name)
            return true
        end,
    })
    return funnel, sent
end

return function(suite: harness.Harness)
    suite:test("a new player joins with session_start then tutorial_start", function()
        local funnel, sent = newFunnel()
        funnel:onJoin(1, 1, 0)
        harness.equal(table.concat(sent, ","), "session_start,tutorial_start", "events")
    end)

    suite:test("a returning player gets session_start only", function()
        local funnel, sent = newFunnel()
        funnel:onJoin(1, 4, 2)
        harness.equal(table.concat(sent, ","), "session_start", "events")
    end)

    suite:test("first_action fires once, on the first accepted press", function()
        local funnel, sent = newFunnel()
        funnel:onJoin(1, 1, 0)
        funnel:onPressAccepted(1)
        funnel:onPressAccepted(1)
        harness.equal(table.concat(sent, ","), "session_start,tutorial_start,first_action")
    end)

    suite:test("first_action also fires for a returning player, once per session", function()
        local funnel, sent = newFunnel()
        funnel:onJoin(1, 2, 3)
        funnel:onPressAccepted(1)
        funnel:onPressAccepted(1)
        harness.equal(table.concat(sent, ","), "session_start,first_action")
    end)

    suite:test("tutorial_complete fires on the first clear of stage 1 only", function()
        local funnel, sent = newFunnel()
        funnel:onJoin(1, 1, 0)
        funnel:onFinishAccepted(1, 1, true)
        funnel:onFinishAccepted(1, 1, false)
        funnel:onFinishAccepted(1, 2, true)
        local complete = 0
        for _, name in sent do
            if name == "tutorial_complete" then
                complete += 1
            end
        end
        harness.equal(complete, 1, "once")
    end)

    suite:test("a returning player never completes the tutorial", function()
        local funnel, sent = newFunnel()
        funnel:onJoin(1, 2, 1)
        funnel:onFinishAccepted(1, 1, false)
        harness.equal(table.concat(sent, ","), "session_start", "no tutorial events")
    end)

    suite:test("events for a player who never joined are ignored; forget resets", function()
        local funnel, sent = newFunnel()
        funnel:onPressAccepted(9)
        funnel:onFinishAccepted(9, 1, true)
        harness.equal(#sent, 0, "ignored")
        funnel:onJoin(1, 1, 0)
        funnel:forget(1)
        funnel:onJoin(1, 2, 0)
        harness.equal(#sent, 4, "joined twice after forget")
    end)
end
