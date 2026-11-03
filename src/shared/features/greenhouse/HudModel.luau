--!strict
--[[
    View model of the minimal greenhouse HUD (ADR 0020). Pure, so the texts, the enabled states and
    the intent a tap maps to are tested under Lune. The client adapter `GreenhouseHud` only draws
    what `view()` returns. Everything held here is a server value the client received; the client
    never computes a price, a timer or a balance. `now` is server time (Unix seconds) passed in by
    the caller, so a wrong local clock can only misdraw a countdown, never grant a harvest: the
    server refuses an early harvest by its own clock.
]]

local GreenhouseData = require("./GreenhouseData")

export type PlotView = {
    plot: number,
    text: string,
    ready: boolean,
}

export type CropButtonView = {
    cropId: string,
    text: string,
    selected: boolean,
}

export type View = {
    coinsText: string,
    plots: { PlotView },
    crops: { CropButtonView },
    sellText: string,
    sellEnabled: boolean,
    buySeedText: string,
    buySeedEnabled: boolean,
    buyPlotText: string,
    buyPlotEnabled: boolean,
    -- The AutoHarvest button: runs the action when owned, opens the pass prompt when not.
    autoHarvestText: string,
    autoHarvestOwned: boolean,
    -- The ExtraPlots pass offer disappears once owned.
    showExtraPlotsOffer: boolean,
}

-- What a tap on a parcel asks the server for. It is a request, not a decision.
export type Intent = { kind: "plant", crop: string } | { kind: "harvest" }

export type HudModel = {
    setCoins: (self: HudModel, coins: number) -> (),
    setPlot: (self: HudModel, plot: number, cropIndex: number, readyAt: number) -> (),
    setStock: (self: HudModel, cropIndex: number, seeds: number, produce: number) -> (),
    setPasses: (self: HudModel, extraPlots: boolean, autoHarvest: boolean) -> (),
    selectCrop: (self: HudModel, cropId: string) -> boolean,
    selectedCrop: (self: HudModel) -> string,
    intentForPlot: (self: HudModel, plot: number, now: number) -> Intent?,
    view: (self: HudModel, now: number) -> View,
}

type PlotState = { cropIndex: number, readyAt: number }
type Stock = { seeds: number, produce: number }

local HudModelModule = {}

local function groupThousands(value: number): string
    local digits = string.format("%d", math.floor(value))
    local spaced = string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")
    local grouped = string.reverse(spaced)
    if string.sub(grouped, 1, 1) == "," then
        grouped = string.sub(grouped, 2)
    end
    return grouped
end

function HudModelModule.new(): HudModel
    local coins = 0
    local plots: { [number]: PlotState } = {}
    local ownedPlots = 0
    local stock: { [string]: Stock } = {}
    for _, crop in GreenhouseData.CROPS do
        stock[crop.id] = { seeds = 0, produce = 0 }
    end
    local ownsExtraPlots = false
    local ownsAutoHarvest = false
    local selected = GreenhouseData.START_SEED_CROP

    local function plotIsReady(state: PlotState, now: number): boolean
        return state.cropIndex > 0 and now >= state.readyAt
    end

    local model: HudModel = {
        setCoins = function(_self: HudModel, newCoins: number)
            coins = newCoins
        end,
        setPlot = function(_self: HudModel, plot: number, cropIndex: number, readyAt: number)
            plots[plot] = { cropIndex = cropIndex, readyAt = readyAt }
            ownedPlots = math.max(ownedPlots, plot)
        end,
        setStock = function(_self: HudModel, cropIndex: number, seeds: number, produce: number)
            local crop = GreenhouseData.cropByIndex(cropIndex)
            if crop ~= nil then
                stock[crop.id] = { seeds = seeds, produce = produce }
            end
        end,
        setPasses = function(_self: HudModel, extraPlots: boolean, autoHarvest: boolean)
            ownsExtraPlots = extraPlots
            ownsAutoHarvest = autoHarvest
        end,
        selectCrop = function(_self: HudModel, cropId: string): boolean
            if GreenhouseData.cropById(cropId) == nil then
                return false
            end
            selected = cropId
            return true
        end,
        selectedCrop = function(_self: HudModel): string
            return selected
        end,
        intentForPlot = function(_self: HudModel, plot: number, now: number): Intent?
            local state = plots[plot]
            if state == nil then
                return nil
            end
            if state.cropIndex == 0 then
                local held = stock[selected]
                if held ~= nil and held.seeds > 0 then
                    return { kind = "plant", crop = selected }
                end
                return nil
            end
            if plotIsReady(state, now) then
                return { kind = "harvest" }
            end
            return nil
        end,
        view = function(_self: HudModel, now: number): View
            local plotViews: { PlotView } = {}
            for plot = 1, ownedPlots do
                local state = plots[plot]
                local text = `Plot {plot}: empty`
                local ready = false
                if state ~= nil and state.cropIndex > 0 then
                    local crop = GreenhouseData.cropByIndex(state.cropIndex)
                    local name = if crop ~= nil then crop.id else "?"
                    ready = plotIsReady(state, now)
                    if ready then
                        text = `Plot {plot}: {name} READY`
                    else
                        text = `Plot {plot}: {name} {math.ceil(state.readyAt - now)}s`
                    end
                end
                table.insert(plotViews, { plot = plot, text = text, ready = ready })
            end

            local cropViews: { CropButtonView } = {}
            local totalProduceValue = 0
            for _, crop in GreenhouseData.CROPS do
                local held = stock[crop.id]
                totalProduceValue += held.produce * crop.sellPrice
                table.insert(cropViews, {
                    cropId = crop.id,
                    text = `{crop.id}: {held.seeds} seeds, {held.produce} produce`,
                    selected = crop.id == selected,
                })
            end

            local selectedSpec = GreenhouseData.cropById(selected)
            local seedPrice = if selectedSpec ~= nil then selectedSpec.seedPrice else 0
            local plotPrice = GreenhouseData.nextPlotPrice(ownedPlots)
            local plotCap = GreenhouseData.maxPlots(ownsExtraPlots)
            local buyPlotText = "Plots maxed"
            local buyPlotEnabled = false
            if ownedPlots < plotCap and plotPrice ~= nil then
                buyPlotText = `Buy plot: {groupThousands(plotPrice)} coins`
                buyPlotEnabled = coins >= plotPrice
            elseif ownedPlots >= GreenhouseData.BASE_MAX_PLOTS and not ownsExtraPlots then
                buyPlotText = "More plots: ExtraPlots pass"
            end

            return {
                coinsText = groupThousands(coins),
                plots = plotViews,
                crops = cropViews,
                sellText = `Sell all: {groupThousands(totalProduceValue)} coins`,
                sellEnabled = totalProduceValue > 0,
                buySeedText = `Buy {selected} seed: {seedPrice} coins`,
                buySeedEnabled = selectedSpec ~= nil and coins >= seedPrice,
                buyPlotText = buyPlotText,
                buyPlotEnabled = buyPlotEnabled,
                autoHarvestText = if ownsAutoHarvest then "Auto harvest" else "Auto harvest (pass)",
                autoHarvestOwned = ownsAutoHarvest,
                showExtraPlotsOffer = not ownsExtraPlots,
            }
        end,
    }
    return model
end

return HudModelModule
