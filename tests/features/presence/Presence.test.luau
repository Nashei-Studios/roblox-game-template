--!strict
local InMemoryFeedStore = require("../../../src/shared/features/presence/InMemoryFeedStore")
local MemoryStoreFeed = require("../../../src/server/adapters/MemoryStoreFeed")
local PresenceBoard = require("../../../src/shared/features/presence/PresenceBoard")
local PresenceConfig = require("../../../src/shared/features/presence/PresenceConfig")
local PresenceEntry = require("../../../src/shared/features/presence/PresenceEntry")
local PresenceFeed = require("../../../src/shared/features/presence/PresenceFeed")
local TextServiceNameFilter = require("../../../src/server/adapters/TextServiceNameFilter")
local harness = require("../../harness")

local function config(): PresenceConfig.PresenceConfig
    local base = PresenceConfig.defaults({
        {
            id = "record",
            pick = "max",
            rows = 1,
            headline = "{name}  {value} pts",
            detail = "Best score  {ago}",
        },
        {
            id = "win",
            pick = "newest",
            rows = 2,
            headline = "{name} won",
            detail = "Round {value}  {ago}",
        },
    })
    base.minGapSeconds = 60
    base.maxEntries = 5
    return base
end

type Rig = {
    clock: { now: number },
    store: InMemoryFeedStore.Store,
    errors: { string },
    feed: PresenceFeed.Feed,
}

local function rig(override: PresenceConfig.PresenceConfig?): Rig
    local clock = { now = 100000 }
    local now = function()
        return clock.now
    end
    local store = InMemoryFeedStore.new(now)
    local errors: { string } = {}
    local feed = PresenceFeed.new({
        config = override or config(),
        store = store,
        filterName = function(_userId: number, name: string): PresenceFeed.NameResult
            if name == "bad" then
                return { ok = false, error = "filtered out" }
            end
            return { ok = true, value = name }
        end,
        now = now,
        onError = function(message: string)
            table.insert(errors, message)
        end,
    })
    return { clock = clock, store = store, errors = errors, feed = feed }
end

local function hasProblem(problems: { string }, needle: string): boolean
    return string.find(table.concat(problems, "|"), needle, 1, true) ~= nil
end

return function(suite: harness.Harness)
    suite:test("the config is valid and each mistake is named", function()
        harness.equal(#PresenceConfig.problems(config()), 0)
        local broken = config()
        broken.kinds = {}
        harness.isTrue(hasProblem(PresenceConfig.problems(broken), "at least one kind"), "none")
        broken = config()
        broken.kinds = {
            { id = "bad id", pick = "min", rows = 9, headline = "", detail = "" },
            { id = "a", pick = "max", rows = 2, headline = "h", detail = "d" },
            { id = "a", pick = "newest", rows = 1, headline = "h", detail = "d" },
        }
        local problems = PresenceConfig.problems(broken)
        harness.isTrue(hasProblem(problems, "letters, digits"), "id")
        harness.isTrue(hasProblem(problems, "pick must be"), "pick")
        harness.isTrue(hasProblem(problems, "rows must be"), "rows")
        harness.isTrue(hasProblem(problems, "shows one row"), "max rows")
        harness.isTrue(hasProblem(problems, "headline and a detail"), "wording")
        harness.isTrue(hasProblem(problems, "declared twice"), "duplicate")
        broken = config()
        broken.maxEntries = 1
        broken.ttlSeconds = 1
        broken.readCacheSeconds = 1
        broken.minGapSeconds = -1
        broken.maxNameLength = 1
        broken.emptyHeadline = ""
        problems = PresenceConfig.problems(broken)
        harness.isTrue(#problems >= 6, `expected six config problems, got {#problems}`)
        broken = config()
        broken.ttlSeconds = PresenceConfig.MAX_STORE_TTL_SECONDS + 1
        harness.isTrue(hasProblem(PresenceConfig.problems(broken), "store limit"), "ttl cap")
    end)

    suite:test("the codec round trips and trusts nothing", function()
        local entry: PresenceEntry.Entry =
            { kind = "win", userId = 7, value = 12, at = 5000, name = "Kira" }
        local text = PresenceEntry.encode(entry)
        harness.equal(text, "win|7|12|5000|Kira")
        local back = PresenceEntry.decode(text)
        harness.isTrue(back ~= nil and back.name == "Kira" and back.value == 12, "round trip")
        harness.equal(PresenceEntry.decode("win|7|12|5000|"), nil, "empty name")
        harness.equal(PresenceEntry.decode("win|x|12|5000|Kira"), nil, "bad user")
        harness.equal(PresenceEntry.decode("win|7|12|5000|a|b"), nil, "extra separator")
        harness.equal(PresenceEntry.decode("garbage"), nil, "garbage")
        harness.equal(PresenceEntry.decode("win|7|-1|5000|Kira"), nil, "negative")
        harness.equal(PresenceEntry.cleanName("a|b\nc", 20), "abc", "separators dropped")
        harness.equal(PresenceEntry.cleanName("abcdef", 3), "abc", "cut")
    end)

    suite:test("record writes a filtered, capped entry and read returns it newest first", function()
        local r = rig()
        harness.equal(r.feed:record("win", 1, "Kira", 3), "recorded")
        r.clock.now += 100
        harness.equal(r.feed:record("win", 2, "Dax", 4), "recorded")
        r.clock.now += 100
        local read = r.feed:read()
        harness.equal(#read, 2)
        harness.equal(read[1].name, "Dax", "newest first")
        harness.equal(#r.errors, 0)
    end)

    suite:test(
        "an undeclared kind, a gap, a failed filter and a failed write are refused",
        function()
            local r = rig()
            harness.equal(r.feed:record("nope", 1, "Kira", 1), "unknown_kind")
            harness.equal(r.feed:record("win", 1, "Kira", 1), "recorded")
            harness.equal(r.feed:record("win", 1, "Kira", 2), "skipped_gap", "same player and kind")
            harness.equal(r.feed:record("record", 1, "Kira", 2), "recorded", "other kind is free")
            harness.equal(r.feed:record("win", 2, "bad", 2), "filter_failed")
            harness.equal(#r.errors, 1)
            harness.equal(
                r.feed:record("win", 3, "|||", 2),
                "filter_failed",
                "name empty after clean"
            )
            r.store.options.failWrites = true
            harness.equal(r.feed:record("win", 4, "Mo", 2), "store_failed")
            harness.isTrue(hasProblem(r.errors, "write failed"), "write error reported")
            r.clock.now += 61
            r.store.options.failWrites = false
            harness.equal(r.feed:record("win", 1, "Kira", 2), "recorded", "gap elapsed")
        end
    )

    suite:test("the feed is capped by removing the oldest", function()
        local r = rig()
        for userId = 1, 8 do
            r.clock.now += 10
            harness.equal(r.feed:record("win", userId, `P{userId}`, userId), "recorded")
        end
        harness.equal(r.store:size(), 5)
        r.clock.now += 100
        local read = r.feed:read()
        harness.equal(#read, 5)
        harness.equal(read[5].name, "P4", "the oldest three are gone")
    end)

    suite:test("reads are cached, failures keep the cache and wait an interval", function()
        local r = rig()
        r.feed:record("win", 1, "Kira", 1)
        harness.equal(#r.feed:read(), 1)
        r.clock.now += 1
        r.feed:record("win", 2, "Dax", 1)
        harness.equal(#r.feed:read(), 2, "a write clears the cache")
        r.clock.now += 5
        r.store.options.failReads = true
        harness.equal(#r.feed:read(), 2, "cached inside the interval")
        r.clock.now += 40
        harness.equal(#r.feed:read(), 2, "failed read keeps the old cache")
        harness.isTrue(hasProblem(r.errors, "read failed"), "read error reported")
        local errorsSoFar = #r.errors
        r.clock.now += 5
        r.feed:read()
        harness.equal(#r.errors, errorsSoFar, "waits a full interval after a failure")
    end)

    suite:test("expired, malformed and undeclared items never come back", function()
        local r = rig()
        local now = r.clock.now
        r.store:add({ key = "a", value = "win|1|1|" .. now .. "|Old", at = now }, 30)
        r.store:add({ key = "b", value = "junk", at = now }, 9999)
        r.store:add({ key = "c", value = "ghost|1|1|" .. now .. "|X", at = now }, 9999)
        r.store:add({ key = "d", value = "win|1|1|" .. (now - 999999) .. "|Stale", at = now }, 9999)
        harness.equal(#r.feed:read(), 1, "only the valid entry survives")
        r.clock.now += 100
        harness.equal(#r.feed:read(), 0, "the short TTL expired it")
        harness.equal(r.store:size(), 3, "the store forgot the short one")
    end)

    suite:test("the board picks the best of a max kind and the newest of a newest kind", function()
        local cfg = config()
        local now = 100000
        local entries: { PresenceEntry.Entry } = {
            { kind = "win", userId = 1, value = 1, at = now - 10, name = "A" },
            { kind = "record", userId = 2, value = 50, at = now - 20, name = "B" },
            { kind = "win", userId = 3, value = 2, at = now - 30, name = "C" },
            { kind = "record", userId = 4, value = 90, at = now - 40, name = "D" },
            { kind = "win", userId = 5, value = 3, at = now - 50, name = "E" },
            { kind = "win", userId = 6, value = 4, at = now - 999999, name = "Old" },
        }
        local board = PresenceBoard.build(entries, now, cfg)
        harness.equal(#board.entries, 3, "one record and two wins")
        harness.equal(board.entries[1].name, "D", "kinds keep their declared order")
        harness.equal(board.entries[2].name, "A")
        harness.equal(board.entries[3].name, "C")
        local rows = PresenceBoard.rows(board.entries, now, cfg)
        harness.equal(rows[1].headline, "D  90 pts")
        harness.equal(rows[1].detail, "Best score  now")
        harness.equal(rows[2].headline, "A won")
        harness.equal(rows[3].detail, "Round 2  now")
    end)

    suite:test("the board survives the wire and words the empty state", function()
        local cfg = config()
        local now = 100000
        local board = PresenceBoard.build({
            { kind = "win", userId = 1, value = 1, at = now - 7200, name = "A" },
        }, now, cfg)
        local decoded = PresenceBoard.decode(PresenceBoard.encode(board) .. "\ngarbage\n")
        harness.equal(#decoded, 1, "malformed lines are skipped")
        local rows = PresenceBoard.rows(decoded, now, cfg)
        harness.equal(rows[1].detail, "Round 1  2h ago")
        local empty = PresenceBoard.rows({}, now, cfg)
        harness.equal(empty[1].headline, cfg.emptyHeadline)
        local foreign = PresenceBoard.rows({
            { kind = "ghost", userId = 1, value = 1, at = now, name = "X" },
        }, now, cfg)
        harness.equal(foreign[1].headline, cfg.emptyHeadline, "an undeclared kind is skipped")
        harness.equal(PresenceBoard.ago(5), "now")
        harness.equal(PresenceBoard.ago(300), "5m ago")
        harness.equal(PresenceBoard.ago(7300), "2h ago")
    end)

    suite:test("the in-memory store honours the port contract", function()
        local clock = 0
        local store = InMemoryFeedStore.new(function()
            return clock
        end)
        store:add({ key = "k", value = "one", at = 1 }, 10)
        store:add({ key = "k", value = "uno", at = 1 }, 10)
        store:add({ key = "j", value = "two", at = 2 }, 10)
        local read = store:recent(5)
        harness.isTrue(read.ok, "read ok")
        if read.ok then
            harness.equal(#read.value, 2, "same key replaces")
            harness.equal(read.value[1].key, "j", "newest first")
        end
        local limited = store:recent(1)
        harness.isTrue(limited.ok and #limited.value == 1, "limit respected")
        harness.isTrue(store:remove("j").ok, "remove ok")
        harness.equal(store:size(), 1)
        clock = 11
        harness.equal(store:size(), 0, "ttl")
        store.options.failReads = true
        harness.isFalse(store:recent(1).ok, "forced read failure")
        store.options.failWrites = true
        harness.isFalse(store:remove("k").ok, "forced remove failure")
    end)

    suite:test(
        "the MemoryStore adapter maps rows, drops foreign ones and types failures",
        function()
            local written: { string } = {}
            local store = MemoryStoreFeed.new({
                handle = {
                    set = function(key: string, value: string, ttl: number, sortKey: number)
                        table.insert(written, `{key}={value}@{sortKey}/{ttl}`)
                    end,
                    range = function(_limit: number)
                        return {
                            { key = "a", value = "win|1|2|3|x", sortKey = 3 },
                            { key = "b", value = 42, sortKey = 2 },
                            { key = "c", value = "text", sortKey = "bad" },
                        }
                    end,
                    remove = function(_key: string) end,
                },
            })
            harness.isTrue(store:add({ key = "k", value = "v", at = 7 }, 86400).ok, "add ok")
            harness.equal(written[1], "k=v@7/86400")
            local read = store:recent(10)
            harness.isTrue(read.ok and #read.value == 1, "only the well formed row")
            harness.isTrue(store:remove("k").ok, "remove ok")

            local down = MemoryStoreFeed.new({
                handle = {
                    set = function()
                        error("set down")
                    end,
                    range = function()
                        error("range down")
                    end,
                    remove = function()
                        error("remove down")
                    end,
                },
            })
            harness.isFalse(down:add({ key = "k", value = "v", at = 7 }, 60).ok, "add failed")
            harness.isFalse(down:remove("k").ok, "remove failed")
            local failed = down:recent(5)
            harness.isFalse(failed.ok, "read failed")
            if not failed.ok then
                harness.equal(failed.error.kind, "store_failed")
                harness.isTrue(hasProblem({ failed.error.message }, "range down"), "message kept")
            end
        end
    )

    suite:test("the name filter adapter returns text or a typed error", function()
        local ok = TextServiceNameFilter.new({
            filter = function(name: string, _userId: number): string
                return `[{name}]`
            end,
        })
        local good = ok(1, "Kira")
        harness.isTrue(good.ok and good.value == "[Kira]", "filtered text")
        local throws = TextServiceNameFilter.new({
            filter = function(_name: string, _userId: number): string
                error("service down")
            end,
        })
        local thrown = throws(1, "Kira")
        harness.isTrue(not thrown.ok and hasProblem({ thrown.error }, "service down"), "throw")
        local empty = TextServiceNameFilter.new({
            filter = function(_name: string, _userId: number): string
                return ""
            end,
        })
        harness.isFalse(empty(1, "Kira").ok, "empty text is refused")
    end)
end
