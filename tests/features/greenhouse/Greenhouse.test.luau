--!strict
local Greenhouse = require("../../../src/shared/features/greenhouse/Greenhouse")
local GreenhouseData = require("../../../src/shared/features/greenhouse/GreenhouseData")
local GrowthTimers = require("../../../src/shared/features/greenhouse/GrowthTimers")
local harness = require("../../harness")

local function newData(): Greenhouse.Slice
    return Greenhouse.newState()
end

local function reason(result: Greenhouse.Outcome<unknown>): string
    if result.ok then
        return "none"
    end
    return result.reason
end

return function(suite: harness.Harness)
    -- GrowthTimers
    suite:test("a planted crop is not ready until the server clock reaches readyAt", function()
        local plot = { cropId = "radish", readyAt = 115 }
        harness.isFalse(GrowthTimers.isReady(plot, 114), "one second early")
        harness.isTrue(GrowthTimers.isReady(plot, 115), "on time")
        harness.equal(GrowthTimers.remaining(plot, 100), 15, "remaining")
    end)

    suite:test("remaining is clamped to growSeconds when the clock moved backwards", function()
        local plot = { cropId = "radish", readyAt = 100000 }
        harness.equal(GrowthTimers.remaining(plot, 50), 15, "clamped")
        harness.equal(GrowthTimers.progress(plot, 50), 0, "no progress")
    end)

    suite:test("an empty plot has no timer and is never ready", function()
        local plot = { cropId = "", readyAt = 0 }
        harness.isTrue(GrowthTimers.isEmpty(plot), "empty")
        harness.isFalse(GrowthTimers.isReady(plot, 999), "not ready")
        harness.equal(GrowthTimers.remaining(plot, 999), 0, "remaining")
        harness.equal(GrowthTimers.progress(plot, 999), 0, "progress")
    end)

    suite:test("progress reaches 1 at the ready time", function()
        local plot = { cropId = "carrot", readyAt = 160 }
        harness.equal(GrowthTimers.progress(plot, 130), 0.5, "halfway")
        harness.equal(GrowthTimers.progress(plot, 160), 1, "done")
    end)

    -- Data
    suite:test("crop wire indexes are 1..n in order and lookups agree", function()
        for position, crop in GreenhouseData.CROPS do
            harness.equal(crop.index, position, "index")
            harness.equal(
                (GreenhouseData.cropById(crop.id) :: GreenhouseData.CropSpec).index,
                position
            )
            harness.equal(
                (GreenhouseData.cropByIndex(position) :: GreenhouseData.CropSpec).id,
                crop.id
            )
        end
        harness.isTrue(GreenhouseData.cropById("nope") == nil, "unknown")
    end)

    suite:test(
        "the first timer is the design's 15 seconds and the price table covers every plot",
        function()
            harness.equal(GreenhouseData.CROPS[1].growSeconds, 15, "first timer")
            harness.equal(#GreenhouseData.PLOT_PRICES, GreenhouseData.ABSOLUTE_MAX_PLOTS, "prices")
            harness.equal(GreenhouseData.maxPlots(false), 6, "base")
            harness.equal(GreenhouseData.maxPlots(true), 10, "with the pass: +4")
            harness.isTrue(GreenhouseData.nextPlotPrice(10) == nil, "no price past the last plot")
        end
    )

    -- Rules
    suite:test("a new player has one empty plot and one radish seed", function()
        local data = newData()
        harness.equal(#data.plots, 1, "plots")
        harness.equal(data.seeds.radish, 1, "seed")
        harness.equal(data.coins, 0, "coins")
    end)

    suite:test("plant spends a seed and sets readyAt from the server clock", function()
        local data = newData()
        harness.isTrue(Greenhouse.plant(data, 1000, 1, "radish").ok, "planted")
        harness.equal(data.seeds.radish, 0, "seed spent")
        harness.equal(data.plots[1].cropId, "radish", "crop")
        harness.equal(data.plots[1].readyAt, 1015, "readyAt")
    end)

    suite:test(
        "plant is refused for a bad plot, an unknown crop, a busy plot or no seeds",
        function()
            local data = newData()
            harness.equal(reason(Greenhouse.plant(data, 0, 2, "radish")), "bad_plot")
            harness.equal(reason(Greenhouse.plant(data, 0, 1, "nope")), "bad_crop")
            harness.equal(reason(Greenhouse.plant(data, 0, 1, "carrot")), "no_seeds")
            Greenhouse.plant(data, 0, 1, "radish")
            data.seeds.radish = 5
            harness.equal(reason(Greenhouse.plant(data, 1, 1, "radish")), "plot_busy")
            harness.equal(data.seeds.radish, 5, "nothing spent on a refusal")
        end
    )

    suite:test("harvest before the server clock says ready changes nothing", function()
        local data = newData()
        Greenhouse.plant(data, 1000, 1, "radish")
        harness.equal(reason(Greenhouse.harvest(data, 1014, 1)), "not_ready")
        harness.equal(data.plots[1].cropId, "radish", "still planted")
        harness.equal(data.produce.radish or 0, 0, "no produce")
        harness.equal(data.totalHarvests, 0, "no harvest counted")
    end)

    suite:test(
        "harvest when ready gives one unit, empties the plot and counts the harvest",
        function()
            local data = newData()
            Greenhouse.plant(data, 1000, 1, "radish")
            local result = Greenhouse.harvest(data, 1015, 1)
            harness.isTrue(result.ok, "harvested")
            harness.equal(data.produce.radish, 1, "produce")
            harness.equal(data.plots[1].cropId, "", "emptied")
            harness.equal(data.plots[1].readyAt, 0, "readyAt reset")
            harness.equal(data.totalHarvests, 1, "counted")
        end
    )

    suite:test("harvest of an empty or missing plot is a typed refusal", function()
        local data = newData()
        harness.equal(reason(Greenhouse.harvest(data, 0, 1)), "plot_empty")
        harness.equal(reason(Greenhouse.harvest(data, 0, 3)), "bad_plot")
    end)

    suite:test("harvest refuses when the produce stock is full (sell first)", function()
        local data = newData()
        Greenhouse.plant(data, 0, 1, "radish")
        data.produce.radish = GreenhouseData.MAX_STOCK
        harness.equal(reason(Greenhouse.harvest(data, 100, 1)), "stock_full")
        harness.equal(data.plots[1].cropId, "radish", "crop stays in the ground")
    end)

    suite:test("sell turns all produce into coins from the data table", function()
        local data = newData()
        data.produce.radish = 2
        data.produce.carrot = 1
        local result = Greenhouse.sell(data)
        harness.isTrue(result.ok, "sold")
        if result.ok then
            harness.equal(result.value, 2 * 12 + 40, "earned")
        end
        harness.equal(data.coins, 64, "coins")
        harness.equal(data.produce.radish, 0, "radish cleared")
        harness.equal(reason(Greenhouse.sell(data)), "nothing_to_sell")
    end)

    suite:test("buy plot charges the derived price and appends an empty plot", function()
        local data = newData()
        data.coins = 10
        harness.isTrue(Greenhouse.buyPlot(data, 6).ok, "bought")
        harness.equal(#data.plots, 2, "plots")
        harness.equal(data.coins, 0, "paid 10")
        harness.equal(data.plots[2].cropId, "", "empty")
        harness.equal(reason(Greenhouse.buyPlot(data, 6)), "not_enough_coins")
    end)

    suite:test("buy plot stops at the cap given by the caller (pass or not)", function()
        local data = newData()
        data.coins = 1000000
        for _ = 2, 6 do
            harness.isTrue(Greenhouse.buyPlot(data, 6).ok, "bought")
        end
        harness.equal(reason(Greenhouse.buyPlot(data, 6)), "max_plots")
        harness.isTrue(Greenhouse.buyPlot(data, 10).ok, "the pass raises the cap")
        harness.equal(#data.plots, 7, "plots")
    end)

    suite:test("buy seed charges the crop price and respects the stock cap", function()
        local data = newData()
        data.coins = 14
        harness.isTrue(Greenhouse.buySeed(data, "carrot").ok, "bought")
        harness.equal(data.seeds.carrot, 1, "seed")
        harness.equal(data.coins, 2, "paid 12")
        harness.equal(reason(Greenhouse.buySeed(data, "carrot")), "not_enough_coins")
        harness.equal(reason(Greenhouse.buySeed(data, "nope")), "bad_crop")
        data.coins = 100
        data.seeds.carrot = GreenhouseData.MAX_STOCK
        harness.equal(reason(Greenhouse.buySeed(data, "carrot")), "stock_full")
    end)

    suite:test("auto harvest collects every ready plot and replants while seeds remain", function()
        local data = newData()
        data.coins = 1000
        Greenhouse.buyPlot(data, 6)
        Greenhouse.buyPlot(data, 6)
        data.seeds.radish = 4
        Greenhouse.plant(data, 0, 1, "radish")
        Greenhouse.plant(data, 0, 2, "radish")
        Greenhouse.plant(data, 100, 3, "radish")
        local result = Greenhouse.autoHarvest(data, 50)
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.equal(#result.value, 2, "two plots changed")
        end
        harness.equal(data.produce.radish, 2, "two harvested")
        harness.equal(data.totalHarvests, 2, "counted")
        harness.equal(data.plots[1].cropId, "radish", "first plot replanted")
        harness.equal(data.plots[2].cropId, "", "no seed left for the second replant")
        harness.equal(data.plots[3].cropId, "radish", "unready plot untouched")
    end)

    suite:test("auto harvest replants the same crop with the server clock", function()
        local data = newData()
        data.seeds.radish = 3
        Greenhouse.plant(data, 0, 1, "radish")
        Greenhouse.autoHarvest(data, 20)
        harness.equal(data.plots[1].cropId, "radish", "replanted")
        harness.equal(data.plots[1].readyAt, 35, "readyAt from the same now")
        harness.equal(data.seeds.radish, 1, "one seed spent")
    end)

    suite:test("auto harvest with nothing ready is a typed refusal", function()
        local data = newData()
        harness.equal(reason(Greenhouse.autoHarvest(data, 0)), "nothing_ready")
    end)
end
