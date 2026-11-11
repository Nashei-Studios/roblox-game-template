--!strict
local AnalyticsServiceSink = require("../../src/server/adapters/AnalyticsServiceSink")
local harness = require("../harness")

type FakePlayer = { UserId: number }
type Logged = {
    player: FakePlayer,
    name: string,
    value: number,
    fields: { [string]: string }?,
}

local function newSink(online: { [number]: FakePlayer }, logged: { Logged })
    return AnalyticsServiceSink.new({
        analytics = {
            LogCustomEvent = function(
                _self: unknown,
                player: FakePlayer,
                name: string,
                value: number,
                fields: { [string]: string }?
            )
                table.insert(
                    logged,
                    { player = player, name = name, value = value, fields = fields }
                )
            end,
        },
        players = {
            GetPlayerByUserId = function(_self: unknown, userId: number): FakePlayer?
                return online[userId]
            end,
        },
        variantFieldKey = "CustomField01",
    })
end

return function(suite: harness.Harness)
    suite:test("logs the event for an online player with name and sessionIndex", function()
        local player: FakePlayer = { UserId = 7 }
        local logged: { Logged } = {}
        local sink = newSink({ [7] = player }, logged)
        sink:log({ name = "session_start", userId = 7, timestamp = 100, sessionIndex = 3 })
        harness.equal(#logged, 1, "calls")
        harness.isTrue(logged[1].player == player, "player")
        harness.equal(logged[1].name, "session_start", "name")
        harness.equal(logged[1].value, 3, "sessionIndex")
    end)

    suite:test("stamps the variant label in the custom field when the event has one", function()
        local player: FakePlayer = { UserId = 7 }
        local logged: { Logged } = {}
        local sink = newSink({ [7] = player }, logged)
        sink:log({
            name = "tutorial_start",
            userId = 7,
            timestamp = 100,
            sessionIndex = 1,
            variant = "onboarding:variant_a",
        })
        local fields = logged[1].fields
        harness.isTrue(fields ~= nil, "fields")
        if fields ~= nil then
            harness.equal(fields.CustomField01, "onboarding:variant_a", "variant")
        end
    end)

    suite:test("sends no custom fields when the event has no variant", function()
        local player: FakePlayer = { UserId = 7 }
        local logged: { Logged } = {}
        local sink = newSink({ [7] = player }, logged)
        sink:log({ name = "session_start", userId = 7, timestamp = 100, sessionIndex = 1 })
        harness.isTrue(logged[1].fields == nil, "no fields")
    end)

    suite:test("drops the event when the player already left", function()
        local logged: { Logged } = {}
        local sink = newSink({}, logged)
        sink:log({ name = "session_start", userId = 7, timestamp = 100, sessionIndex = 1 })
        harness.equal(#logged, 0, "calls")
    end)
end
