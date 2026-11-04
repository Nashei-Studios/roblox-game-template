--!strict
local PerfBudget = require("../../src/shared/perf/PerfBudget")
local RemoteBudget = require("../../src/shared/perf/RemoteBudget")
local harness = require("../harness")

local SCHEMA = [[
opt casing = "camelCase"
-- a comment with event Fake = { from: Client, data: u32 }
type Kind = enum { "A", "B" }
event Buy = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (kind: Kind),
}
event Coins = {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (coins: u32, note: string(0..20), flag: bool?),
}
]]

local function budget(): PerfBudget.Budget
    return {
        perEventOverheadBytes = 8,
        clientToServerBytesPerSecond = 100,
        serverToClientBytesPerSecond = 1000,
        perRemoteBytesPerSecond = 500,
        clientRemotes = { Buy = { capacity = 3, refillPerSecond = 1 } },
        serverRemotes = { Coins = { maxPerSecond = 2 } },
        runtime = PerfBudget.runtime,
    }
end

local function parse(text: string): { RemoteBudget.EventSpec }
    local parsed = RemoteBudget.parseSchema(text)
    if not parsed.ok then
        error(parsed.error)
    end
    return parsed.value
end

return function(suite: harness.Harness)
    suite:test("parses events, ignores commented ones and sizes payloads", function()
        local events = parse(SCHEMA)
        harness.equal(#events, 2)
        harness.equal(events[1].name, "Buy")
        harness.equal(events[1].from, "Client")
        harness.equal(events[1].payloadBytes, 1) -- enum with 2 variants
        harness.equal(events[2].name, "Coins")
        harness.equal(events[2].payloadBytes, 4 + (2 + 20) + 2) -- u32, string(0..20), bool?
    end)

    suite:test("computes the worst case from the rate limit and passes", function()
        local report = RemoteBudget.evaluate(parse(SCHEMA), budget())
        harness.equal(#report.failures, 0)
        harness.equal(report.clientToServerBytesPerSecond, (1 + 8) * 4)
        harness.equal(report.serverToClientBytesPerSecond, (28 + 8) * 2)
        harness.equal(#report.rows, 2)
    end)

    suite:test("fails when a remote exceeds the per-remote budget", function()
        local tight = budget()
        tight.perRemoteBytesPerSecond = 30
        local report = RemoteBudget.evaluate(parse(SCHEMA), tight)
        harness.equal(#report.failures, 2)
    end)

    suite:test("fails when a direction total exceeds its budget", function()
        local tight = budget()
        tight.clientToServerBytesPerSecond = 10
        tight.serverToClientBytesPerSecond = 10
        local report = RemoteBudget.evaluate(parse(SCHEMA), tight)
        harness.equal(#report.failures, 2)
    end)

    suite:test("fails on a remote with no declared rate", function()
        local missing = budget()
        missing.clientRemotes = {}
        local report = RemoteBudget.evaluate(parse(SCHEMA), missing)
        harness.isTrue(#report.failures >= 1, "failure expected")
        harness.isTrue(string.find(report.failures[1], "Buy", 1, true) ~= nil, "names Buy")
    end)

    suite:test("fails on a budgeted remote the schema does not have", function()
        local stale = budget()
        stale.clientRemotes.Gone = { capacity = 1, refillPerSecond = 1 }
        stale.serverRemotes.AlsoGone = { maxPerSecond = 1 }
        local report = RemoteBudget.evaluate(parse(SCHEMA), stale)
        harness.equal(#report.failures, 2)
    end)

    suite:test("rejects unbounded and unknown types", function()
        local unbounded = RemoteBudget.parseSchema(
            "event E = { from: Client, type: Reliable, call: SingleSync, data: (s: string) }"
        )
        harness.isFalse(unbounded.ok, "unbounded string")
        local unknown = RemoteBudget.parseSchema(
            "event E = { from: Client, type: Reliable, call: SingleSync, data: (i: Instance) }"
        )
        harness.isFalse(unknown.ok, "unknown type")
    end)

    suite:test("rejects a bad direction, a missing data field and an empty enum", function()
        harness.isFalse(
            RemoteBudget.parseSchema("event E = { from: Both, data: u8 }").ok,
            "direction"
        )
        harness.isFalse(RemoteBudget.parseSchema("event E = { from: Client }").ok, "no data")
        harness.isFalse(RemoteBudget.parseSchema("type T = enum { }").ok, "empty enum")
    end)

    suite:test("handles bare data, empty data and enums wider than 256 variants", function()
        local bare = parse("event E = { from: Server, data: f64 }")
        harness.equal(bare[1].payloadBytes, 8)
        local variants: { string } = {}
        for index = 1, 300 do
            table.insert(variants, `"V{index}"`)
        end
        local wide = parse(
            `type W = enum \{ {table.concat(variants, ", ")} \}\nevent E = \{ from: Server, data: (w: W) \}`
        )
        harness.equal(wide[1].payloadBytes, 2)
    end)

    suite:test("the shipped budget passes the shipped schema contract", function()
        local report = RemoteBudget.evaluate({
            { name = "RequestPurchase", from = "Client", payloadBytes = 1 },
            { name = "CoinsChanged", from = "Server", payloadBytes = 4 },
            { name = "RedeemCode", from = "Client", payloadBytes = 34 },
            { name = "ClaimDailyReward", from = "Client", payloadBytes = 0 },
            { name = "ClaimSessionGift", from = "Client", payloadBytes = 26 },
            { name = "SetVolume", from = "Client", payloadBytes = 2 },
            { name = "Notify", from = "Server", payloadBytes = 5 },
            { name = "SoundSettings", from = "Server", payloadBytes = 2 },
        }, PerfBudget)
        harness.equal(#report.failures, 0)
    end)
end
