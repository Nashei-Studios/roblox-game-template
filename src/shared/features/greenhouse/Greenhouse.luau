--!strict
--[[
    The rules of the greenhouse loop over a slice of player data (ADR 0020): plant, harvest,
    sell, buy a plot, buy a seed, auto-harvest. Pure: `now` is passed in (the caller reads the
    server Clock port), so the client can never say that a timer finished. Each function either
    mutates the slice and returns ok, or returns a typed reason and leaves it untouched.
]]

local GreenhouseData = require("./GreenhouseData")
local GrowthTimers = require("./GrowthTimers")

export type Plot = { cropId: string, readyAt: number }

-- The slice of PlayerData the loop reads and writes.
export type Slice = {
    coins: number,
    plots: { Plot },
    seeds: { [string]: number },
    produce: { [string]: number },
    totalHarvests: number,
}

export type Reason =
    "bad_plot"
    | "bad_crop"
    | "plot_busy"
    | "plot_empty"
    | "not_ready"
    | "no_seeds"
    | "nothing_to_sell"
    | "nothing_ready"
    | "not_enough_coins"
    | "max_plots"
    | "no_price"
    | "stock_full"

export type Outcome<T> = { ok: true, value: T } | { ok: false, reason: Reason }

local Greenhouse = {}

-- Largest integer a Luau number holds exactly; coins never pass it.
Greenhouse.MAX_COINS = 2 ^ 53

local function refuse(reason: Reason): { ok: false, reason: Reason }
    return { ok = false, reason = reason }
end

--- A fresh state for a new player: START_PLOTS empty plots and the starting seed.
function Greenhouse.newState(): Slice
    local plots: { Plot } = {}
    for _ = 1, GreenhouseData.START_PLOTS do
        table.insert(plots, { cropId = "", readyAt = 0 })
    end
    return {
        coins = 0,
        plots = plots,
        seeds = { [GreenhouseData.START_SEED_CROP] = GreenhouseData.START_SEED_COUNT },
        produce = {},
        totalHarvests = 0,
    }
end

local function plantAt(data: Slice, now: number, plot: Plot, crop: GreenhouseData.CropSpec)
    data.seeds[crop.id] = (data.seeds[crop.id] or 0) - 1
    plot.cropId = crop.id
    plot.readyAt = now + crop.growSeconds
end

local function harvestAt(data: Slice, plot: Plot)
    data.produce[plot.cropId] = (data.produce[plot.cropId] or 0) + 1
    data.totalHarvests += 1
    plot.cropId = ""
    plot.readyAt = 0
end

function Greenhouse.plant(data: Slice, now: number, plotIndex: number, cropId: string): Outcome<nil>
    local plot = data.plots[plotIndex]
    if plot == nil then
        return refuse("bad_plot")
    end
    local crop = GreenhouseData.cropById(cropId)
    if crop == nil then
        return refuse("bad_crop")
    end
    if not GrowthTimers.isEmpty(plot) then
        return refuse("plot_busy")
    end
    if (data.seeds[crop.id] or 0) < 1 then
        return refuse("no_seeds")
    end
    plantAt(data, now, plot, crop)
    return { ok = true, value = nil }
end

--- Returns the harvested crop id. Ready means `now >= readyAt` on the SERVER clock.
function Greenhouse.harvest(data: Slice, now: number, plotIndex: number): Outcome<string>
    local plot = data.plots[plotIndex]
    if plot == nil then
        return refuse("bad_plot")
    end
    if GrowthTimers.isEmpty(plot) then
        return refuse("plot_empty")
    end
    if not GrowthTimers.isReady(plot, now) then
        return refuse("not_ready")
    end
    if (data.produce[plot.cropId] or 0) >= GreenhouseData.MAX_STOCK then
        return refuse("stock_full")
    end
    local cropId = plot.cropId
    harvestAt(data, plot)
    return { ok = true, value = cropId }
end

--- Sells all produce at the data-table prices. Returns the coins earned.
function Greenhouse.sell(data: Slice): Outcome<number>
    local earned = 0
    for cropId, count in data.produce do
        local crop = GreenhouseData.cropById(cropId)
        if crop ~= nil and count > 0 then
            earned += count * crop.sellPrice
        end
    end
    if earned <= 0 then
        return refuse("nothing_to_sell")
    end
    for cropId in data.produce do
        data.produce[cropId] = 0
    end
    data.coins = math.min(Greenhouse.MAX_COINS, data.coins + earned)
    return { ok = true, value = earned }
end

--- Buys the next plot at the price derived from the saved plot count. `maxPlots` comes from the
--- caller (GreenhouseData.maxPlots with the server-read pass). Returns the new plot count.
function Greenhouse.buyPlot(data: Slice, maxPlots: number): Outcome<number>
    local owned = #data.plots
    if owned >= maxPlots then
        return refuse("max_plots")
    end
    local price = GreenhouseData.nextPlotPrice(owned)
    if price == nil then
        return refuse("no_price")
    end
    if data.coins < price then
        return refuse("not_enough_coins")
    end
    data.coins -= price
    table.insert(data.plots, { cropId = "", readyAt = 0 })
    return { ok = true, value = #data.plots }
end

function Greenhouse.buySeed(data: Slice, cropId: string): Outcome<nil>
    local crop = GreenhouseData.cropById(cropId)
    if crop == nil then
        return refuse("bad_crop")
    end
    if (data.seeds[crop.id] or 0) >= GreenhouseData.MAX_STOCK then
        return refuse("stock_full")
    end
    if data.coins < crop.seedPrice then
        return refuse("not_enough_coins")
    end
    data.coins -= crop.seedPrice
    data.seeds[crop.id] = (data.seeds[crop.id] or 0) + 1
    return { ok = true, value = nil }
end

--- Harvests every ready plot and replants the same crop while seeds remain. Returns the plot
--- indexes that changed. The pass check is the caller's (GreenhouseController).
function Greenhouse.autoHarvest(data: Slice, now: number): Outcome<{ number }>
    local changed: { number } = {}
    for index, plot in data.plots do
        if GrowthTimers.isReady(plot, now) then
            local cropId = plot.cropId
            local crop = GreenhouseData.cropById(cropId)
            if crop ~= nil and (data.produce[cropId] or 0) < GreenhouseData.MAX_STOCK then
                harvestAt(data, plot)
                if (data.seeds[cropId] or 0) >= 1 then
                    plantAt(data, now, plot, crop)
                end
                table.insert(changed, index)
            end
        end
    end
    if #changed == 0 then
        return refuse("nothing_ready")
    end
    return { ok = true, value = changed }
end

return Greenhouse
