--!strict
local Config = require("../../../src/shared/Config")
local Podium = require("../../../src/shared/features/podium/Podium")
local PodiumConfig = require("../../../src/shared/features/podium/PodiumConfig")
local PodiumFormat = require("../../../src/shared/features/podium/PodiumFormat")
local PodiumLayout = require("../../../src/shared/features/podium/PodiumLayout")
local PodiumModel = require("../../../src/shared/features/podium/PodiumModel")
local PodiumNames = require("../../../src/shared/features/podium/PodiumNames")
local PodiumSources = require("../../../src/shared/features/podium/PodiumSources")
local OrderedBoardStore = require("../../../src/shared/ports/OrderedBoardStore")
local PerfBudget = require("../../../src/shared/perf/PerfBudget")
local RarityConfig = require("../../../src/shared/features/rarity/RarityConfig")
local harness = require("../../harness")

local RARITY = RarityConfig.default
local SURFACE = "#171C30"

local function copyConfig(): PodiumConfig.PodiumConfig
    local copy = table.clone(PodiumConfig.default)
    copy.placeTierIds = table.clone(copy.placeTierIds)
    copy.layout = table.clone(copy.layout)
    copy.layout.stepHeights = table.clone(copy.layout.stepHeights)
    return copy
end

local function problems(config: PodiumConfig.PodiumConfig): { string }
    return PodiumConfig.problems(config, RARITY, 60)
end

type Rig = {
    clock: { now: number },
    source: PodiumSources.InMemory,
    errors: { string },
    podium: Podium.Podium,
}

local function rig(): Rig
    local clock = { now = 1000 }
    local errors: { string } = {}
    local source = PodiumSources.inMemory({
        { userId = 11, value = 12500 },
        { userId = 22, value = 900 },
        { userId = 33, value = 7 },
    })
    local podium = Podium.new({
        config = copyConfig(),
        rarity = RARITY,
        surfaceHex = SURFACE,
        source = source,
        nameOf = function(userId: number): string
            return `Miner{userId}`
        end,
        now = function(): number
            return clock.now
        end,
        onError = function(message: string)
            table.insert(errors, message)
        end,
    })
    return { clock = clock, source = source, errors = errors, podium = podium }
end

return function(suite: harness.Harness)
    suite:test("default config is valid and the budget floor matches it", function()
        harness.equal(#problems(PodiumConfig.default), 0)
        local budget = PerfBudget.podium
        harness.isTrue(budget ~= nil, "PerfBudget.podium exists")
        harness.isTrue(Config.default.podium ~= nil, "Config.default.podium exists")
        if budget ~= nil then
            harness.equal(
                #PodiumConfig.problems(PodiumConfig.default, RARITY, budget.minRefreshSeconds),
                0
            )
            harness.isTrue(budget.maxParts >= 9, "budget fits at least steps, plates and a statue")
        end
    end)

    suite:test("config problems are reported one per broken rule", function()
        local config = copyConfig()
        config.refreshSeconds = 5
        config.placeTierIds = { "legendary", "nope" }
        config.emptyLabel = ""
        config.idleAnimationId = "http://evil"
        config.nameMaxLength = 2
        config.layout.stepHeights = { 2, 3, 4 }
        harness.equal(#problems(config), 7)
    end)

    suite:test("compact values", function()
        harness.equal(PodiumFormat.compact(0), "0")
        harness.equal(PodiumFormat.compact(999.9), "999")
        harness.equal(PodiumFormat.compact(1000), "1.0K")
        harness.equal(PodiumFormat.compact(1250), "1.2K")
        harness.equal(PodiumFormat.compact(9990), "9.9K")
        harness.equal(PodiumFormat.compact(12500), "12K")
        harness.equal(PodiumFormat.compact(3400000), "3.4M")
        harness.equal(PodiumFormat.compact(5600000000), "5.6B")
        harness.equal(PodiumFormat.compact(2e12), "2T")
        harness.equal(PodiumFormat.compact(-4), "0")
        harness.equal(PodiumFormat.compact(0 / 0), "0")
        harness.equal(PodiumFormat.value(1250, "m"), "1.2K m")
        harness.equal(PodiumFormat.value(7, ""), "7")
    end)

    suite:test("layout puts place 1 in the middle and tallest, 2 left, 3 right", function()
        local slots = PodiumLayout.slots(PodiumConfig.default.layout)
        harness.equal(#slots, 3)
        harness.equal(slots[1].standPoint.x, 0)
        harness.isTrue(slots[2].standPoint.x < 0, "place 2 on the left")
        harness.isTrue(slots[3].standPoint.x > 0, "place 3 on the right")
        harness.isTrue(slots[1].standPoint.y > slots[2].standPoint.y, "1 above 2")
        harness.isTrue(slots[2].standPoint.y > slots[3].standPoint.y, "2 above 3")
        harness.equal(slots[1].stepCenter.y, slots[1].stepSize.y / 2)
        local footprint = PodiumLayout.footprint(PodiumConfig.default.layout)
        harness.equal(footprint.x, 5 * 3 + 0.5 * 2)
    end)

    suite:test("model fills three places with medal colors and formatted values", function()
        local config = copyConfig()
        config.valueUnit = "m"
        local view = PodiumModel.build(config, RARITY, SURFACE, {
            { userId = 11, value = 12500 },
            { userId = 22, value = 900 },
            { userId = 33, value = 7 },
            { userId = 44, value = 1 },
        }, function(userId: number): string
            return `Miner{userId}`
        end)
        harness.equal(#view.places, 3)
        harness.equal(view.occupiedCount, 3)
        harness.equal(view.places[1].headline, "Miner11")
        harness.equal(view.places[1].detail, "12K m")
        harness.equal(view.places[1].tierLabel, "Legendary")
        harness.equal(view.places[1].frameHex, "#FF8A3D")
        harness.equal(view.places[2].frameHex, "#B26BFF")
        harness.equal(view.places[3].frameHex, "#4D8DFF")
        harness.isTrue(view.places[1].glow, "legendary glows")
    end)

    suite:test("missing places become empty pedestals with the Be the first plate", function()
        local view = PodiumModel.build(copyConfig(), RARITY, SURFACE, {
            { userId = 11, value = 5 },
        }, function(): string
            return "Solo"
        end)
        harness.equal(view.occupiedCount, 1)
        harness.isTrue(not view.places[2].occupied, "place 2 empty")
        harness.equal(view.places[2].headline, "Be the first")
        harness.equal(view.places[2].detail, "")
        harness.equal(view.places[3].tierLabel, "")
        harness.isFalse(view.places[3].glow, "empty pedestal has no glow")
        local empty = PodiumModel.empty(copyConfig(), RARITY, SURFACE)
        harness.equal(empty.occupiedCount, 0)
        harness.equal(empty.places[1].headline, "Be the first")
    end)

    suite:test("long names are cut with an ellipsis", function()
        harness.equal(PodiumModel.cutName("short", 16), "short")
        harness.equal(PodiumModel.cutName("ABCDEFGHIJKLMNOPQRST", 10), "ABCDEFG...")
    end)

    suite:test("names: filtered, cached, and a failure never shows a raw name", function()
        local lookups = 0
        local errors: { string } = {}
        local failFilter = false
        local nameOf = PodiumNames.new({
            lookup = function(userId: number): string
                lookups += 1
                if userId == 99 then
                    error("http 500")
                end
                return `Raw{userId}`
            end,
            filter = function(_userId: number, name: string): PodiumNames.NameResult
                if failFilter then
                    return { ok = false, error = "filter down" }
                end
                return { ok = true, value = `[{name}]` }
            end,
            unknownName = "Player",
            onError = function(message: string)
                table.insert(errors, message)
            end,
        })
        harness.equal(nameOf(1), "[Raw1]")
        harness.equal(nameOf(1), "[Raw1]")
        harness.equal(lookups, 1)
        harness.equal(nameOf(99), "Player")
        failFilter = true
        harness.equal(nameOf(2), "Player")
        harness.equal(#errors, 2)
        failFilter = false
        harness.equal(nameOf(2), "[Raw2]")
    end)

    suite:test("first tick reads, builds the view and reports a change", function()
        local r = rig()
        harness.isTrue(r.podium:tick(), "first tick is a change")
        harness.equal(r.source:reads(), 1)
        harness.equal(r.podium:view().places[1].headline, "Miner11")
    end)

    suite:test("the cache holds for refreshSeconds and refreshes after", function()
        local r = rig()
        r.podium:tick()
        r.clock.now += 59
        harness.isFalse(r.podium:tick(), "inside the interval")
        harness.equal(r.source:reads(), 1)
        r.source:set({ { userId = 22, value = 50000 } })
        r.clock.now += 1
        harness.isTrue(r.podium:tick(), "interval passed and the board changed")
        harness.equal(r.source:reads(), 2)
        harness.equal(r.podium:view().places[1].headline, "Miner22")
        harness.equal(r.podium:view().occupiedCount, 1)
        r.clock.now += 60
        harness.isFalse(r.podium:tick(), "same data, nothing to rebuild")
    end)

    suite:test(
        "a failing source shows empty pedestals, never throws, and waits a full interval",
        function()
            local r = rig()
            r.source:setFailing(true)
            harness.isTrue(r.podium:tick(), "first tick still draws the fallback")
            harness.equal(r.podium:view().occupiedCount, 0)
            harness.equal(r.podium:view().places[1].headline, "Be the first")
            harness.equal(#r.errors, 1)
            r.clock.now += 30
            r.podium:tick()
            harness.equal(r.source:reads(), 1)
        end
    )

    suite:test("a failure after a good read keeps the last good view", function()
        local r = rig()
        r.podium:tick()
        r.source:setFailing(true)
        r.clock.now += 60
        harness.isFalse(r.podium:tick(), "nothing changed on screen")
        harness.equal(r.podium:view().places[1].headline, "Miner11")
        harness.equal(#r.errors, 1)
        r.source:setFailing(false)
        r.clock.now += 60
        r.podium:tick()
        harness.equal(#r.errors, 1)
    end)

    suite:test("sources: store passthrough, cache with nil, error mapping", function()
        local asked: { string } = {}
        local failing = false
        local store: OrderedBoardStore.OrderedBoardStore = {
            setScore = function(): OrderedBoardStore.SetResult
                return { ok = true, value = nil }
            end,
            top = function(
                _self: OrderedBoardStore.OrderedBoardStore,
                boardKey: string,
                size: number
            ): OrderedBoardStore.TopResult
                table.insert(asked, `{boardKey}:{size}`)
                if failing then
                    return { ok = false, error = { kind = "store_failed", message = "boom" } }
                end
                return {
                    ok = true,
                    value = {
                        { userId = 1, value = 3 },
                        { userId = 2, value = 2 },
                        { userId = 3, value = 1 },
                        { userId = 4, value = 0 },
                    },
                }
            end,
        }
        local fromStore = PodiumSources.fromStore(store, function(): string
            return "Coins"
        end)
        local read = fromStore:top(3)
        harness.equal(asked[1], "Coins:3")
        harness.isTrue(read.ok and #read.value == 3, "sliced to 3")
        failing = true
        local failed = fromStore:top(3)
        harness.isTrue(not failed.ok, "failure maps to an error")
        local fromCache = PodiumSources.fromCache(function()
            return nil
        end)
        local notReady = fromCache:top(3)
        harness.isTrue(notReady.ok and #notReady.value == 0, "nil cache reads as nobody yet")
    end)
end
