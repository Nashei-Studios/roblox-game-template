--!strict
local Funnel = require("../../../src/shared/features/reef/Funnel")
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
        funnel:onJoin(1, 4, 12)
        harness.equal(table.concat(sent, ","), "session_start", "events")
    end)

    suite:test("first_action fires once, on the first accepted cast", function()
        local funnel, sent = newFunnel()
        funnel:onJoin(1, 1, 0)
        funnel:onCastAccepted(1)
        funnel:onCastAccepted(1)
        harness.equal(table.concat(sent, ","), "session_start,tutorial_start,first_action")
    end)

    suite:test("tutorial_complete fires once, on the first rod of a tutorial player", function()
        local funnel, sent = newFunnel()
        funnel:onJoin(1, 1, 0)
        funnel:onRodBought(1)
        funnel:onRodBought(1)
        harness.equal(table.concat(sent, ","), "session_start,tutorial_start,tutorial_complete")
    end)

    suite:test("a returning player never completes the tutorial", function()
        local funnel, sent = newFunnel()
        funnel:onJoin(1, 2, 5)
        funnel:onRodBought(1)
        harness.equal(table.concat(sent, ","), "session_start", "events")
    end)

    suite:test("events for an unknown or forgotten player are ignored", function()
        local funnel, sent = newFunnel()
        funnel:onCastAccepted(9)
        funnel:onRodBought(9)
        funnel:onJoin(1, 1, 0)
        funnel:forget(1)
        funnel:onCastAccepted(1)
        harness.equal(table.concat(sent, ","), "session_start,tutorial_start", "events")
    end)
end
