--!strict
--[[
    View model of the minimal HUD (pure, so the text and the enabled states are tested under
    Lune). The client adapter `ReefHud` only draws what `view()` returns; it holds no rules.
    Everything shown here is a server value the client received, never one it computed. The
    rod price shown is the table price for display; the server derives the real one on purchase.
]]

local ReefConfig = require("./ReefConfig")

export type Phase = "idle" | "waiting" | "bite"

export type View = {
    phase: Phase,
    statusText: string,
    coinsText: string,
    stockText: string,
    -- Cast is offered when idle; Reel when the line is out.
    showCast: boolean,
    showReel: boolean,
    upgradeText: string,
    upgradeEnabled: boolean,
    sellEnabled: boolean,
}

export type HudModel = {
    setCoins: (self: HudModel, coins: number) -> (),
    setRod: (self: HudModel, rodLevel: number) -> (),
    setStock: (self: HudModel, count: number, capacity: number) -> (),
    castStarted: (self: HudModel) -> (),
    bite: (self: HudModel) -> (),
    -- `fishId` is nil when the catch was missed.
    catchResult: (self: HudModel, fishId: string?) -> (),
    view: (self: HudModel) -> View,
}

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

function HudModelModule.new(table_: ReefConfig.ReefTable): HudModel
    local phase: Phase = "idle"
    local coins = 0
    local rodLevel = 1
    local stockCount = 0
    local capacity = 0
    local lastResult = "Cast your line"

    local model: HudModel = {
        setCoins = function(_self: HudModel, newCoins: number)
            coins = newCoins
        end,
        setRod = function(_self: HudModel, newLevel: number)
            rodLevel = newLevel
        end,
        setStock = function(_self: HudModel, count: number, newCapacity: number)
            stockCount = count
            capacity = newCapacity
        end,
        castStarted = function(_self: HudModel)
            phase = "waiting"
            lastResult = "Waiting for a bite..."
        end,
        bite = function(_self: HudModel)
            phase = "bite"
            lastResult = "Bite! Reel now"
        end,
        catchResult = function(_self: HudModel, fishId: string?)
            phase = "idle"
            if fishId == nil then
                lastResult = "It got away. Cast again"
            else
                lastResult = `Caught a {fishId}!`
            end
        end,
        view = function(_self: HudModel): View
            local nextRod = ReefConfig.rod(table_, rodLevel + 1)
            local upgradeText = "Best rod owned"
            if nextRod ~= nil then
                upgradeText = `Next rod: {nextRod.price} coins`
            end
            return {
                phase = phase,
                statusText = lastResult,
                coinsText = groupThousands(coins),
                stockText = `Fish {stockCount} / {capacity}`,
                showCast = phase == "idle",
                showReel = phase ~= "idle",
                upgradeText = upgradeText,
                upgradeEnabled = nextRod ~= nil and coins >= nextRod.price,
                sellEnabled = stockCount > 0,
            }
        end,
    }
    return model
end

return HudModelModule
