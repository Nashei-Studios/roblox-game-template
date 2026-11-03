--!strict
local HudModel = require("../../../src/shared/features/greenhouse/HudModel")
local harness = require("../../harness")

local function kindOf(intent: HudModel.Intent?): string
    if intent == nil then
        return "none"
    end
    return intent.kind
end

return function(suite: harness.Harness)
    suite:test("a fresh HUD has no plots, zero coins and radish selected", function()
        local hud = HudModel.new()
        local view = hud:view(0)
        harness.equal(view.coinsText, "0", "coins")
        harness.equal(#view.plots, 0, "plots")
        harness.equal(#view.crops, 3, "crop buttons")
        harness.equal(hud:selectedCrop(), "radish", "selected")
        harness.isFalse(view.sellEnabled, "nothing to sell")
    end)

    suite:test("coins are grouped by thousands", function()
        local hud = HudModel.new()
        hud:setCoins(1234567)
        harness.equal(hud:view(0).coinsText, "1,234,567", "grouped")
        hud:setCoins(999)
        harness.equal(hud:view(0).coinsText, "999", "small")
    end)

    suite:test("a growing plot shows a countdown and turns READY at the server time", function()
        local hud = HudModel.new()
        hud:setPlot(1, 1, 115)
        harness.equal(hud:view(100).plots[1].text, "Plot 1: radish 15s", "growing")
        harness.isFalse(hud:view(100).plots[1].ready, "not ready")
        harness.equal(hud:view(114.5).plots[1].text, "Plot 1: radish 1s", "rounded up")
        harness.equal(hud:view(115).plots[1].text, "Plot 1: radish READY", "ready")
        harness.isTrue(hud:view(115).plots[1].ready, "ready flag")
    end)

    suite:test("an empty plot shows empty and rows run up to the highest plot seen", function()
        local hud = HudModel.new()
        hud:setPlot(2, 0, 0)
        local plots = hud:view(0).plots
        harness.equal(#plots, 2, "two rows")
        harness.equal(plots[1].text, "Plot 1: empty", "unseen plot is empty")
        harness.equal(plots[2].text, "Plot 2: empty", "empty plot")
    end)

    suite:test("a tap plants only with a seed in stock and only an empty plot", function()
        local hud = HudModel.new()
        hud:setPlot(1, 0, 0)
        harness.equal(kindOf(hud:intentForPlot(1, 0)), "none", "no seeds")
        hud:setStock(1, 2, 0)
        local intent = hud:intentForPlot(1, 0)
        harness.equal(kindOf(intent), "plant", "plant")
        local crop = ""
        if intent ~= nil and intent.kind == "plant" then
            crop = intent.crop
        end
        harness.equal(crop, "radish", "crop")
        harness.equal(kindOf(hud:intentForPlot(9, 0)), "none", "unknown plot")
    end)

    suite:test("a tap harvests a ready plot and ignores a growing one", function()
        local hud = HudModel.new()
        hud:setPlot(1, 2, 200)
        harness.equal(kindOf(hud:intentForPlot(1, 199)), "none", "growing")
        harness.equal(kindOf(hud:intentForPlot(1, 200)), "harvest", "ready")
    end)

    suite:test("selecting a crop accepts known ids only", function()
        local hud = HudModel.new()
        harness.isTrue(hud:selectCrop("pumpkin"), "known")
        harness.equal(hud:selectedCrop(), "pumpkin", "selected")
        harness.isFalse(hud:selectCrop("potato"), "unknown")
        harness.equal(hud:selectedCrop(), "pumpkin", "unchanged")
        local selectedCount = 0
        for _, button in hud:view(0).crops do
            if button.selected then
                selectedCount += 1
            end
        end
        harness.equal(selectedCount, 1, "one selected")
    end)

    suite:test("stock drives the sell value and the buy seed state", function()
        local hud = HudModel.new()
        hud:setStock(1, 0, 2)
        hud:setStock(2, 1, 1)
        hud:setStock(9, 5, 5)
        local view = hud:view(0)
        harness.equal(view.sellText, "Sell all: 64 coins", "2*12 + 1*40")
        harness.isTrue(view.sellEnabled, "sellable")
        harness.isFalse(view.buySeedEnabled, "no coins")
        hud:setCoins(3)
        harness.isTrue(hud:view(0).buySeedEnabled, "radish seed costs 3")
        harness.equal(hud:view(0).buySeedText, "Buy radish seed: 3 coins", "text")
    end)

    suite:test("the plot button prices the next plot and explains the cap", function()
        local hud = HudModel.new()
        hud:setPlot(1, 0, 0)
        harness.equal(hud:view(0).buyPlotText, "Buy plot: 10 coins", "next price")
        harness.isFalse(hud:view(0).buyPlotEnabled, "broke")
        hud:setCoins(10)
        harness.isTrue(hud:view(0).buyPlotEnabled, "affordable")
        for plot = 2, 6 do
            hud:setPlot(plot, 0, 0)
        end
        harness.equal(hud:view(0).buyPlotText, "More plots: ExtraPlots pass", "base cap")
        harness.isFalse(hud:view(0).buyPlotEnabled, "capped")
        hud:setPasses(true, false)
        harness.equal(hud:view(0).buyPlotText, "Buy plot: 1,500 coins", "extra plots owned")
        harness.isFalse(hud:view(0).showExtraPlotsOffer, "offer gone")
        for plot = 7, 10 do
            hud:setPlot(plot, 0, 0)
        end
        harness.equal(hud:view(0).buyPlotText, "Plots maxed", "absolute cap")
    end)

    suite:test("the auto harvest button reflects the pass", function()
        local hud = HudModel.new()
        harness.isFalse(hud:view(0).autoHarvestOwned, "not owned")
        harness.equal(hud:view(0).autoHarvestText, "Auto harvest (pass)", "offer")
        hud:setPasses(false, true)
        harness.isTrue(hud:view(0).autoHarvestOwned, "owned")
        harness.equal(hud:view(0).autoHarvestText, "Auto harvest", "action")
    end)
end
