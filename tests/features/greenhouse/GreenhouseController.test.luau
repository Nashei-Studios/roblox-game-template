--!strict
local Greenhouse = require("../../../src/shared/features/greenhouse/Greenhouse")
local GreenhouseController = require("../../../src/shared/features/greenhouse/GreenhouseController")
local GreenhouseData = require("../../../src/shared/features/greenhouse/GreenhouseData")
local Funnel = require("../../../src/shared/features/greenhouse/Funnel")
local harness = require("../../harness")

type Fixture = {
    controller: GreenhouseController.GreenhouseController,
    data: Greenhouse.Slice,
    events: { string },
    setNow: (seconds: number) -> (),
    setAllowed: (allowed: boolean) -> (),
    passes: { [string]: boolean },
}

local function newFixture(): Fixture
    local data = Greenhouse.newState()
    local now = 1000
    local allowed = true
    local events: { string } = {}
    local passes: { [string]: boolean } = {}
    local funnel = Funnel.new({
        track = function(name: string, _userId: number, _sessionIndex: number): boolean
            table.insert(events, name)
            return true
        end,
    })
    local clock = {
        now = function(_self: unknown): number
            return now
        end,
    }
    local controller = GreenhouseController.new({
        clock = clock,
        dataFor = function(userId: number): Greenhouse.Slice?
            if userId == 1 then
                return data
            end
            return nil
        end,
        allow = function(_userId: number, _remote: string): boolean
            return allowed
        end,
        ownsPass = function(_userId: number, passName: string): boolean
            return passes[passName] == true
        end,
        funnel = funnel,
    })
    return {
        controller = controller,
        data = data,
        events = events,
        setNow = function(seconds: number)
            now = seconds
        end,
        setAllowed = function(value: boolean)
            allowed = value
        end,
        passes = passes,
    }
end

local function reason(result: GreenhouseController.HandleResult): string
    if result.ok then
        return "none"
    end
    return result.reason
end

type Recorded = {
    plots: { string },
    stock: { string },
    coins: { number },
    passes: { string },
}

local function flushOf(fixture: Fixture): Recorded
    local recorded: Recorded = { plots = {}, stock = {}, coins = {}, passes = {} }
    fixture.controller:flush(1, {
        plot = function(plot: number, cropIndex: number, readyAt: number)
            table.insert(recorded.plots, `{plot}:{cropIndex}:{readyAt}`)
        end,
        stock = function(cropIndex: number, seeds: number, produce: number)
            table.insert(recorded.stock, `{cropIndex}:{seeds}:{produce}`)
        end,
        coins = function(coins: number)
            table.insert(recorded.coins, coins)
        end,
        passes = function(extraPlots: boolean, autoHarvest: boolean)
            table.insert(recorded.passes, `{extraPlots}:{autoHarvest}`)
        end,
    })
    return recorded
end

return function(suite: harness.Harness)
    suite:test("plant uses the server clock, not anything the client sends", function()
        local fixture = newFixture()
        fixture.setNow(2000)
        harness.isTrue(fixture.controller:plant(1, 1, "radish").ok, "planted")
        harness.equal(fixture.data.plots[1].readyAt, 2015, "readyAt = server now + grow")
    end)

    suite:test("harvest is refused until the SERVER clock passes readyAt", function()
        local fixture = newFixture()
        fixture.controller:plant(1, 1, "radish")
        fixture.setNow(1014)
        harness.equal(reason(fixture.controller:harvest(1, 1)), "not_ready")
        fixture.setNow(1015)
        harness.isTrue(fixture.controller:harvest(1, 1).ok, "ready on the server clock")
        harness.equal(fixture.data.produce.radish, 1, "produce")
    end)

    suite:test("a flooded client is dropped before anything is read", function()
        local fixture = newFixture()
        fixture.setAllowed(false)
        harness.equal(reason(fixture.controller:plant(1, 1, "radish")), "rate_limited")
        harness.equal(fixture.data.seeds.radish, 1, "nothing changed")
    end)

    suite:test("arguments are validated: plot range, integer, crop allow-list", function()
        local fixture = newFixture()
        harness.equal(reason(fixture.controller:plant(1, 0, "radish")), "out_of_range", "zero")
        harness.equal(reason(fixture.controller:plant(1, 11, "radish")), "out_of_range", "high")
        harness.equal(reason(fixture.controller:plant(1, 1.5, "radish")), "not_an_integer", "float")
        harness.equal(reason(fixture.controller:plant(1, "1", "radish")), "not_a_number", "string")
        harness.equal(reason(fixture.controller:plant(1, 1, "weed")), "not_allowed", "crop")
        harness.equal(reason(fixture.controller:plant(1, 1, 7)), "not_a_string", "crop type")
        harness.equal(reason(fixture.controller:harvest(1, 0 / 0)), "not_finite", "nan")
        harness.equal(reason(fixture.controller:buySeed(1, "weed")), "not_allowed", "seed")
    end)

    suite:test("a player without loaded data is refused", function()
        local fixture = newFixture()
        harness.equal(reason(fixture.controller:sell(2)), "no_data")
    end)

    suite:test("a plot beyond the owned count is refused by the rules", function()
        local fixture = newFixture()
        harness.equal(reason(fixture.controller:plant(1, 2, "radish")), "bad_plot")
    end)

    suite:test("sell and buy plot re-derive prices on the server", function()
        local fixture = newFixture()
        fixture.data.produce.radish = 1
        harness.isTrue(fixture.controller:sell(1).ok, "sold")
        harness.equal(fixture.data.coins, 12, "coins")
        harness.isTrue(fixture.controller:buyPlot(1).ok, "bought")
        harness.equal(fixture.data.coins, 2, "paid the table price, 10")
        harness.equal(#fixture.data.plots, 2, "plots")
    end)

    suite:test("the plot cap is 6 without the pass and 10 with it, read from the server", function()
        local fixture = newFixture()
        fixture.data.coins = 1000000
        for _ = 2, 6 do
            fixture.controller:buyPlot(1)
        end
        harness.equal(reason(fixture.controller:buyPlot(1)), "max_plots")
        fixture.passes[GreenhouseData.PASS_EXTRA_PLOTS] = true
        harness.isTrue(fixture.controller:buyPlot(1).ok, "pass raises the cap")
        harness.equal(#fixture.data.plots, 7, "plots")
    end)

    suite:test("auto harvest needs the pass and checks it on the server", function()
        local fixture = newFixture()
        fixture.controller:plant(1, 1, "radish")
        fixture.setNow(2000)
        harness.equal(reason(fixture.controller:autoHarvest(1)), "pass_required")
        harness.equal(fixture.data.plots[1].cropId, "radish", "untouched")
        fixture.passes[GreenhouseData.PASS_AUTO_HARVEST] = true
        harness.isTrue(fixture.controller:autoHarvest(1).ok, "with the pass")
        harness.equal(fixture.data.produce.radish, 1, "harvested")
    end)

    suite:test("flush sends only dirty plots, then nothing until something changes", function()
        local fixture = newFixture()
        fixture.controller:join(1, 1)
        local first = flushOf(fixture)
        harness.equal(#first.plots, 1, "join syncs every plot")
        harness.equal(first.plots[1], "1:0:0", "empty plot on the wire: crop 0")
        harness.equal(#first.stock, 3, "stock of every crop")
        harness.equal(first.stock[1], "1:1:0", "radish seeds 1")
        harness.equal(first.coins[1], 0, "coins")
        harness.equal(first.passes[1], "false:false", "passes")
        local second = flushOf(fixture)
        harness.equal(#second.plots + #second.stock + #second.coins + #second.passes, 0, "idle")
        fixture.controller:plant(1, 1, "radish")
        local third = flushOf(fixture)
        harness.equal(third.plots[1], "1:1:1015", "planted plot with the server readyAt")
        harness.equal(#third.plots, 1, "only that plot")
    end)

    suite:test("a refused action resyncs the plot it targeted", function()
        local fixture = newFixture()
        fixture.controller:join(1, 1)
        flushOf(fixture)
        fixture.controller:harvest(1, 1)
        local recorded = flushOf(fixture)
        harness.equal(recorded.plots[1], "1:0:0", "client gets the server truth back")
    end)

    suite:test("flush clamps wire values to their field sizes", function()
        local fixture = newFixture()
        fixture.data.coins = 2 ^ 40
        fixture.data.plots[1].cropId = "radish"
        fixture.data.plots[1].readyAt = 2 ^ 40
        fixture.controller:join(1, 1)
        local recorded = flushOf(fixture)
        harness.equal(recorded.coins[1], 4294967295, "u32 coins")
        harness.equal(recorded.plots[1], "1:1:4294967295", "u32 readyAt")
    end)

    suite:test("passesChanged and markDirty schedule a resync", function()
        local fixture = newFixture()
        fixture.controller:join(1, 1)
        flushOf(fixture)
        fixture.passes[GreenhouseData.PASS_EXTRA_PLOTS] = true
        fixture.controller:passesChanged(1)
        harness.equal(flushOf(fixture).passes[1], "true:false", "passes resent")
        fixture.data.coins = 50
        fixture.controller:markDirty(1)
        harness.equal(flushOf(fixture).coins[1], 50, "coins resent after a grant")
    end)

    suite:test(
        "funnel: session_start and tutorial_start on join, first_action on first plant",
        function()
            local fixture = newFixture()
            fixture.controller:join(1, 1)
            fixture.controller:plant(1, 1, "radish")
            harness.equal(
                table.concat(fixture.events, ","),
                "session_start,tutorial_start,first_action"
            )
        end
    )

    suite:test("funnel: tutorial_complete fires on the first accepted sell only", function()
        local fixture = newFixture()
        fixture.controller:join(1, 1)
        fixture.controller:sell(1)
        harness.equal(
            table.concat(fixture.events, ","),
            "session_start,tutorial_start",
            "refused sell"
        )
        fixture.controller:plant(1, 1, "radish")
        fixture.setNow(1015)
        fixture.controller:harvest(1, 1)
        fixture.controller:sell(1)
        fixture.data.produce.radish = 1
        fixture.controller:sell(1)
        local complete = 0
        for _, name in fixture.events do
            if name == "tutorial_complete" then
                complete += 1
            end
        end
        harness.equal(complete, 1, "once")
    end)

    suite:test("funnel: a returning player gets neither tutorial event", function()
        local fixture = newFixture()
        fixture.data.totalHarvests = 3
        fixture.controller:join(1, 4)
        fixture.data.produce.radish = 1
        fixture.controller:sell(1)
        harness.equal(table.concat(fixture.events, ","), "session_start", "events")
    end)

    suite:test("leave forgets the player", function()
        local fixture = newFixture()
        fixture.controller:join(1, 1)
        fixture.controller:leave(1)
        local recorded = flushOf(fixture)
        harness.equal(#recorded.plots, 0, "nothing to flush after leaving")
    end)
end
