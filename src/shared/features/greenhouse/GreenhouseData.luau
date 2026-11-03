--!strict
--[[
    The numbers of the greenhouse loop (ADR 0020). Pure data and lookups: no engine services.

    Every figure here is "chosen, not measured": there is no playtest or telemetry behind it.
    They are tuned in this file only; rules and tests read them from here.
]]

export type CropSpec = {
    id: string,
    -- Wire index (1-based). 0 on the wire means "no crop".
    index: number,
    -- Seconds the server clock needs between planting and ready.
    growSeconds: number,
    -- Coins for one seed, and coins for one harvested unit.
    seedPrice: number,
    sellPrice: number,
}

local GreenhouseData = {}

--- In wire-index order. The 15 s radish is the first timer of the design (first 60 seconds).
GreenhouseData.CROPS = {
    { id = "radish", index = 1, growSeconds = 15, seedPrice = 3, sellPrice = 12 },
    { id = "carrot", index = 2, growSeconds = 60, seedPrice = 12, sellPrice = 40 },
    { id = "pumpkin", index = 3, growSeconds = 300, seedPrice = 70, sellPrice = 240 },
} :: { CropSpec }

GreenhouseData.START_PLOTS = 1
GreenhouseData.BASE_MAX_PLOTS = 6
-- ExtraPlots pass: permanent plots added on top of BASE_MAX_PLOTS (design: +4).
GreenhouseData.EXTRA_PLOTS_BONUS = 4
-- Largest plot count any player can have; sizes the wire (u8) and the generated parcels.
GreenhouseData.ABSOLUTE_MAX_PLOTS = GreenhouseData.BASE_MAX_PLOTS + GreenhouseData.EXTRA_PLOTS_BONUS

--- Coins to buy the plot number n (index = n). The first plot is free (START_PLOTS = 1).
GreenhouseData.PLOT_PRICES = { 0, 10, 40, 120, 350, 800, 1500, 2500, 4000, 6000 } :: { number }

-- Per-crop cap for seeds and for unsold produce (fits the u16 of the wire, and keeps a profile small).
GreenhouseData.MAX_STOCK = 9999

-- Game pass names; they mirror Config.default.gamePasses and the PassName enum of net/schema.zap.
GreenhouseData.PASS_EXTRA_PLOTS = "ExtraPlots"
GreenhouseData.PASS_AUTO_HARVEST = "AutoHarvest"

GreenhouseData.START_SEED_CROP = "radish"
GreenhouseData.START_SEED_COUNT = 1

function GreenhouseData.cropById(id: string): CropSpec?
    for _, crop in GreenhouseData.CROPS do
        if crop.id == id then
            return crop
        end
    end
    return nil
end

function GreenhouseData.cropByIndex(index: number): CropSpec?
    return GreenhouseData.CROPS[index]
end

--- Every crop id, in wire order (the allow-list for Validation.oneOf).
function GreenhouseData.cropIds(): { string }
    local ids: { string } = {}
    for _, crop in GreenhouseData.CROPS do
        table.insert(ids, crop.id)
    end
    return ids
end

--- The plot cap for a player; the pass is read from Roblox by the caller, never from the client.
function GreenhouseData.maxPlots(ownsExtraPlots: boolean): number
    if ownsExtraPlots then
        return GreenhouseData.ABSOLUTE_MAX_PLOTS
    end
    return GreenhouseData.BASE_MAX_PLOTS
end

--- Price of the next plot for a player who owns `ownedPlots`, or nil past the price table.
function GreenhouseData.nextPlotPrice(ownedPlots: number): number?
    return GreenhouseData.PLOT_PRICES[ownedPlots + 1]
end

return GreenhouseData
