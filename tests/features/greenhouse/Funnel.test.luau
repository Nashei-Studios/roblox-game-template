--!strict
local Funnel = require("../../../src/shared/features/greenhouse/Funnel")
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

    suite:test("first_action fires once per session, also for a returning player", function()
        local funnel, sent = newFunnel()
        funnel:onJoin(1, 2, 3)
        funnel:onPlantAccepted(1)
        funnel:onPlantAccepted(1)
        harness.equal(table.concat(sent, ","), "session_start,first_action", "events")
    end)

    suite:test("tutorial_complete fires on the first sell of a tutorial player, once", function()
        local funnel, sent = newFunnel()
        funnel:onJoin(1, 1, 0)
        funnel:onSellAccepted(1)
        funnel:onSellAccepted(1)
        harness.equal(table.concat(sent, ","), "session_start,tutorial_start,tutorial_complete")
    end)

    suite:test("events for an unknown or forgotten player are ignored", function()
        local funnel, sent = newFunnel()
        funnel:onPlantAccepted(9)
        funnel:onSellAccepted(9)
        funnel:onJoin(1, 1, 0)
        funnel:forget(1)
        funnel:onPlantAccepted(1)
        harness.equal(table.concat(sent, ","), "session_start,tutorial_start", "events")
    end)
end
