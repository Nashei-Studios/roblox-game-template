--!strict
--[[
    View model of the minimal HUD (pure, so the text and the enabled states are tested under
    Lune). The client adapter `KeySprintHud` only draws what `view()` returns; it holds no rules.
    Everything shown here is a server value the client received, never one it computed.
]]

local KeySprintRules = require("./KeySprintRules")
local Progression = require("./Progression")

export type View = {
    -- 0..1: where the multiplier is between 1 and the cap.
    meterFill: number,
    multiplierText: string,
    coinsText: string,
    showKeyPrompt: boolean,
    promptText: string,
    upgradeText: string,
    upgradeEnabled: boolean,
    stageText: string,
    -- The Skip stage button is offered while a stage remains.
    showSkip: boolean,
}

export type HudModel = {
    setMultiplier: (self: HudModel, multiplier: number, cap: number) -> (),
    setProgress: (self: HudModel, highestStage: number, cap: number) -> (),
    setCoins: (self: HudModel, coins: number) -> (),
    -- The player pressed a key: the prompt can go away.
    notePress: (self: HudModel) -> (),
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

function HudModelModule.new(): HudModel
    local multiplier = 1
    local cap = KeySprintRules.BASE_CAP
    local highestStage = 0
    local coins = 0
    local pressed = false

    local model: HudModel = {
        setMultiplier = function(_self: HudModel, newMultiplier: number, newCap: number)
            multiplier = newMultiplier
            cap = newCap
        end,
        setProgress = function(_self: HudModel, newHighestStage: number, newCap: number)
            highestStage = newHighestStage
            cap = newCap
        end,
        setCoins = function(_self: HudModel, newCoins: number)
            coins = newCoins
        end,
        notePress = function(_self: HudModel)
            pressed = true
        end,
        view = function(_self: HudModel): View
            local fill = 1
            if cap > 1 then
                fill = math.clamp((multiplier - 1) / (cap - 1), 0, 1)
            end
            local price = Progression.nextCapPrice(cap)
            local upgradeText = "Cap maxed"
            if price ~= nil then
                upgradeText = `Upgrade cap: {price} coins`
            end
            local stageText = "All stages cleared"
            if highestStage < KeySprintRules.STAGE_COUNT then
                stageText = `Stage {highestStage + 1} of {KeySprintRules.STAGE_COUNT}`
            end
            return {
                meterFill = fill,
                multiplierText = string.format("x%.1f / x%g", multiplier, cap),
                coinsText = groupThousands(coins),
                showKeyPrompt = not pressed,
                promptText = `Press {KeySprintRules.PRESS_KEY_NAME}`,
                upgradeText = upgradeText,
                upgradeEnabled = price ~= nil and coins >= price,
                stageText = stageText,
                showSkip = highestStage < KeySprintRules.STAGE_COUNT,
            }
        end,
    }
    return model
end

return HudModelModule
