--!strict
local JoinProbeSink = require("../../../src/shared/features/joinprobe/JoinProbeSink")
local harness = require("../../harness")

-- 2026-11-06 23:59:59 UTC
local NOW = 1794009599

local function fakeStore(): (JoinProbeSink.StoreLike, { [string]: { JoinProbeSink.Entry } })
    local data: { [string]: { JoinProbeSink.Entry } } = {}
    local store: JoinProbeSink.StoreLike = {
        UpdateAsync = function(_self: unknown, key: string, transform: JoinProbeSink.Transform)
            data[key] = transform(data[key]) :: { JoinProbeSink.Entry }
            return data[key]
        end,
    }
    return store, data
end

return function(suite: harness.Harness)
    suite:test("key is the UTC date plus the user id", function()
        harness.equal(JoinProbeSink.key(NOW, 42), "2026-11-06:42", "key")
        harness.equal(JoinProbeSink.key(NOW + 1, 42), "2026-11-07:42", "next UTC day")
    end)

    suite:test("entry copies the fields and adds rx and at, nothing else", function()
        local entry = JoinProbeSink.entry({ kind = "server", joinS = 1.5 }, "server", NOW)
        harness.equal(entry.kind, "server", "kind")
        harness.equal(entry.joinS, 1.5, "joinS")
        harness.equal(entry.rx, "server", "rx")
        harness.equal(entry.at, NOW, "at")
        local count = 0
        for _ in entry do
            count += 1
        end
        harness.equal(count, 4, "no Data fields")
    end)

    suite:test("record appends under the day key", function()
        local store, data = fakeStore()
        local sink = JoinProbeSink.new({
            store = store,
            now = function()
                return NOW
            end,
            warn = function() end,
        })
        harness.equal(sink:record(7, { kind = "server" }, "server"), true, "ok")
        harness.equal(sink:record(7, { kind = "client" }, "client"), true, "ok2")
        local list = data["2026-11-06:7"]
        harness.equal(#list, 2, "two entries")
        harness.equal(list[2].rx, "client", "order kept")
    end)

    suite:test("the list is capped at the last 40", function()
        local old: { JoinProbeSink.Entry } = {}
        for i = 1, 45 do
            old = JoinProbeSink.append(old, { n = i })
        end
        harness.equal(#old, JoinProbeSink.CAP, "cap")
        harness.equal(old[1].n, 6, "oldest dropped")
        harness.equal(old[40].n, 45, "newest kept")
    end)

    suite:test("a port error is counted, warned once and never thrown", function()
        local warnings = 0
        local sink = JoinProbeSink.new({
            store = {
                UpdateAsync = function(): unknown
                    error("boom")
                end,
            },
            now = function()
                return NOW
            end,
            warn = function()
                warnings += 1
            end,
        })
        harness.equal(sink:record(1, {}, "server"), false, "first")
        harness.equal(sink:record(1, {}, "server"), false, "second")
        harness.equal(sink:failures(), 2, "counted")
        harness.equal(warnings, 1, "warned once")
    end)

    suite:test("wiring needs both flags and a live server", function()
        harness.equal(JoinProbeSink.shouldWire(true, true, false), true, "live")
        harness.equal(JoinProbeSink.shouldWire(false, true, false), false, "probe off")
        harness.equal(JoinProbeSink.shouldWire(true, false, false), false, "sink off")
        harness.equal(JoinProbeSink.shouldWire(true, true, true), false, "studio")
    end)
end
