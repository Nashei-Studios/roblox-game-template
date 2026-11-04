--!strict
local BoardKey = require("../../../src/shared/features/leaderboards/BoardKey")
local Leaderboards = require("../../../src/shared/features/leaderboards/Leaderboards")
local LeaderboardsConfig = require("../../../src/shared/features/leaderboards/LeaderboardsConfig")
local OrderedBoardStore = require("../../../src/shared/ports/OrderedBoardStore")
local PlayerStats = require("../../../src/shared/features/leaderboards/PlayerStats")
local Ports = require("../../../src/shared/ports/Leaderboards")
local harness = require("../../harness")

type Fixture = {
    service: Ports.Leaderboards,
    clock: { now: number },
    profile: PlayerStats.StatProfile,
    writes: { string },
    reads: { string },
    shown: { string },
    published: { string },
    errors: { string },
    store: { failWrites: boolean, failReads: boolean, top: { OrderedBoardStore.Entry } },
}

local function validConfig(): LeaderboardsConfig.LeaderboardsConfig
    return {
        leaderstats = { "coins" },
        writeSeconds = 60,
        boards = {
            Coins = { stat = "coins", refreshSeconds = 120, size = 10, resetCycle = "never" },
            Daily = { stat = "sessions", refreshSeconds = 300, size = 5, resetCycle = "daily" },
        },
    }
end

local function newFixture(): Fixture
    local clock = { now = 1_000_000 }
    local profile: PlayerStats.StatProfile = { coins = 5, sessionCount = 2 }
    local writes: { string } = {}
    local reads: { string } = {}
    local shown: { string } = {}
    local published: { string } = {}
    local errors: { string } = {}
    local control =
        { failWrites = false, failReads = false, top = {} :: { OrderedBoardStore.Entry } }
    local store: OrderedBoardStore.OrderedBoardStore = {
        setScore = function(
            _self: OrderedBoardStore.OrderedBoardStore,
            key: string,
            userId: number,
            value: number
        )
            if control.failWrites then
                return { ok = false, error = { kind = "store_failed", message = "throttled" } }
            end
            table.insert(writes, `{key}/{userId}={value}`)
            return { ok = true, value = nil }
        end,
        top = function(_self: OrderedBoardStore.OrderedBoardStore, key: string, _size: number)
            table.insert(reads, key)
            if control.failReads then
                return { ok = false, error = { kind = "store_failed", message = "down" } }
            end
            return { ok = true, value = control.top }
        end,
    }
    local view: Ports.StatView = {
        set = function(_self: Ports.StatView, userId: number, stat: string, value: number)
            table.insert(shown, `{userId}:{stat}={value}`)
        end,
        remove = function(_self: Ports.StatView, userId: number)
            table.insert(shown, `{userId}:removed`)
        end,
    }
    local publisher: Ports.BoardPublisher = {
        publish = function(
            _self: Ports.BoardPublisher,
            boardId: string,
            entries: { Ports.Entry },
            _at: number
        )
            table.insert(published, `{boardId}:{#entries}`)
        end,
    }
    local service = Leaderboards.new({
        config = validConfig(),
        store = store,
        view = view,
        publisher = publisher,
        now = function(): number
            return clock.now
        end,
        profileFor = function(userId: number): PlayerStats.StatProfile?
            if userId == 1 then
                return profile
            end
            return nil
        end,
        onError = function(message: string)
            table.insert(errors, message)
        end,
    })
    return {
        service = service,
        clock = clock,
        profile = profile,
        writes = writes,
        reads = reads,
        shown = shown,
        published = published,
        errors = errors,
        store = control,
    }
end

return function(suite: harness.Harness)
    suite:test(
        "joining fills leaderstats from the profile and reads nothing from the store",
        function()
            local fixture = newFixture()
            fixture.service:track(1)
            harness.equal(fixture.shown[1], "1:coins=5", "leaderstats shown")
            harness.equal(#fixture.reads, 0, "no read on join")
            harness.equal(#fixture.writes, 0, "no write on join")
        end
    )

    suite:test("writes run on the schedule and only for changed values", function()
        local fixture = newFixture()
        fixture.service:track(1)
        fixture.service:tick()
        harness.equal(#fixture.writes, 2, "first round writes both boards")
        fixture.clock.now += 30
        fixture.service:tick()
        harness.equal(#fixture.writes, 2, "not due yet")
        fixture.clock.now += 40
        fixture.service:tick()
        harness.equal(#fixture.writes, 2, "due but unchanged")
        fixture.profile.coins = 9
        fixture.clock.now += 61
        fixture.service:tick()
        harness.equal(#fixture.writes, 3, "only the changed board")
        harness.equal(fixture.writes[3], "Coins/1=9")
    end)

    suite:test("reads follow each board's refresh interval and are cached and published", function()
        local fixture = newFixture()
        fixture.store.top = { { userId = 1, value = 9 } }
        fixture.service:tick()
        harness.equal(#fixture.reads, 2, "both boards read once")
        harness.equal(#fixture.published, 2, "both published")
        harness.equal(#(fixture.service:top("Coins") or {}), 1, "cached")
        fixture.clock.now += 119
        fixture.service:tick()
        harness.equal(#fixture.reads, 2, "not due")
        fixture.clock.now += 2
        fixture.service:tick()
        harness.equal(#fixture.reads, 3, "only the 120 s board is due")
        harness.isTrue(fixture.service:top("Missing") == nil, "unknown board")
    end)

    suite:test("a failed read keeps the cache and waits a full interval", function()
        local fixture = newFixture()
        fixture.store.top = { { userId = 1, value = 9 } }
        fixture.service:tick()
        fixture.store.failReads = true
        fixture.clock.now += 130
        fixture.service:tick()
        harness.equal(#(fixture.service:top("Coins") or {}), 1, "old cache kept")
        harness.isTrue(#fixture.errors >= 1, "reported with context")
        local reads = #fixture.reads
        fixture.clock.now += 10
        fixture.service:tick()
        harness.equal(#fixture.reads, reads, "no retry before the next interval")
    end)

    suite:test("a failed write is reported and retried at the next round", function()
        local fixture = newFixture()
        fixture.service:track(1)
        fixture.store.failWrites = true
        fixture.service:tick()
        harness.equal(#fixture.writes, 0, "nothing stored")
        harness.isTrue(#fixture.errors >= 1, "reported")
        fixture.store.failWrites = false
        fixture.clock.now += 61
        fixture.service:tick()
        harness.equal(#fixture.writes, 2, "retried")
    end)

    suite:test("forgetting a player flushes once and drops the view", function()
        local fixture = newFixture()
        fixture.service:track(1)
        fixture.profile.coins = 50
        fixture.service:forget(1)
        harness.equal(#fixture.writes, 2, "final flush")
        harness.equal(fixture.shown[#fixture.shown], "1:removed")
        fixture.service:forget(1)
        harness.equal(#fixture.writes, 2, "second forget does nothing")
        fixture.clock.now += 61
        fixture.service:tick()
        harness.equal(#fixture.writes, 2, "no longer tracked")
    end)

    suite:test("a new reset period writes under a new key", function()
        local fixture = newFixture()
        fixture.service:track(1)
        fixture.service:tick()
        fixture.clock.now += 86400
        fixture.service:tick()
        local sawNewKey = false
        for _, write in fixture.writes do
            sawNewKey = sawNewKey or string.find(write, "Daily_d12", 1, true) ~= nil
        end
        harness.isTrue(sawNewKey, "daily key carries the period")
        harness.equal(#fixture.writes, 3, "the all-time board is unchanged")
    end)

    suite:test("a player with no loaded data is skipped", function()
        local fixture = newFixture()
        fixture.service:track(2)
        fixture.service:tick()
        harness.equal(#fixture.shown, 0, "nothing to show")
        harness.equal(#fixture.writes, 0, "nothing to write")
    end)

    suite:test("validate reports every problem", function()
        harness.equal(#LeaderboardsConfig.validate(validConfig()), 0, "valid")
        local bad: LeaderboardsConfig.LeaderboardsConfig = {
            leaderstats = { "coins", "coins", "gems", "a", "b" },
            writeSeconds = 5,
            boards = {
                ["bad id"] = { stat = "gems", refreshSeconds = 10, size = 0, resetCycle = "never" },
            },
        }
        local problems = LeaderboardsConfig.validate(bad)
        harness.isTrue(#problems >= 9, `expected many problems, got {#problems}`)
        local crowded = validConfig()
        for index = 1, 6 do
            crowded.boards[`B{index}`] =
                { stat = "coins", refreshSeconds = 60, size = 3, resetCycle = "never" }
        end
        local budget = LeaderboardsConfig.validate(crowded)
        harness.isTrue(#budget >= 1, "read budget exceeded")
    end)

    suite:test("board keys, periods and wire text", function()
        harness.equal(BoardKey.storeKey("Coins", "never", 5), "Coins")
        harness.equal(BoardKey.storeKey("Coins", "daily", 86400 * 3), "Coins_d3")
        -- 1970-01-05 is the first Monday: day 4 starts week 1; day 3 (Sunday) is week 0.
        harness.equal(BoardKey.period("weekly", 86400 * 3), 0, "Sunday still week 0")
        harness.equal(BoardKey.period("weekly", 86400 * 4), 1, "Monday starts week 1")
        harness.equal(BoardKey.period("never", 99999999), 0)
        local text = BoardKey.encode({ { userId = 12, value = 340 }, { userId = 7, value = 5 } })
        harness.equal(text, "12:340;7:5")
        local decoded = BoardKey.decode(text .. ";junk;1:x")
        harness.equal(#decoded, 2, "junk skipped")
        harness.equal(decoded[1].value, 340)
        local entries, stamp = BoardKey.decodePublished("12:340;7:5|1234")
        harness.equal(#entries, 2, "published entries")
        harness.equal(stamp, 1234, "published time")
        local _, missing = BoardKey.decodePublished("12:340")
        harness.equal(missing, 0, "no time")
    end)

    suite:test("stats are read as non-negative integers", function()
        harness.equal(PlayerStats.read({ coins = 7.9, sessionCount = 3 }, "coins"), 7)
        harness.equal(PlayerStats.read({ coins = -4, sessionCount = 3 }, "coins"), 0)
        harness.equal(PlayerStats.read({ coins = 1, sessionCount = 3 }, "sessions"), 3)
        harness.isTrue(PlayerStats.read({ coins = 1, sessionCount = 3 }, "gems") == nil, "unknown")
        harness.isTrue(PlayerStats.read({ coins = 0 / 0, sessionCount = 3 }, "coins") == nil, "NaN")
    end)
end
