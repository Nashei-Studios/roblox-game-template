--!strict
--[[
    Client entry point (ADR 0020). Thin adapter: it sends intent (plant, harvest, sell, buy) and
    draws what HudModel returns. It owns no rules and trusts nothing it computes: coins, stock,
    timers and passes shown here are server values. A tap that the model thinks is useless is not
    sent, but the server re-checks every request by its own clock, prices and balances.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GreenhouseData = require(Shared.features.greenhouse.GreenhouseData)
local HudModel = require(Shared.features.greenhouse.HudModel)
local net = require(Shared.net.generated.client)

local GreenhouseHud = require(script.Parent.GreenhouseHud)

print(`{Config.default.gameName} client started`)

-- Mirrors the CropName enum of net/schema.zap (the generated client does not export it).
type CropName = "radish" | "carrot" | "pumpkin"

local model = HudModel.new()

local function serverNow(): number
    return Workspace:GetServerTimeNow()
end

-- The wire enum is closed; this narrows a model string to it (the model only holds known ids).
local function asCrop(cropId: string): CropName?
    if cropId == "radish" then
        return "radish"
    elseif cropId == "carrot" then
        return "carrot"
    elseif cropId == "pumpkin" then
        return "pumpkin"
    end
    return nil
end

local hud: GreenhouseHud.GreenhouseHud? = nil
local function redraw()
    if hud ~= nil then
        hud:render(model:view(serverNow()))
    end
end

hud = GreenhouseHud.new({
    onSelectCrop = function(cropId: string)
        model:selectCrop(cropId)
        redraw()
    end,
    onSell = function()
        net.Sell.fire()
    end,
    onBuySeed = function()
        local crop: CropName? = asCrop(model:selectedCrop())
        if crop ~= nil then
            net.BuySeed.fire(crop)
        end
    end,
    onBuyPlot = function()
        net.BuyPlot.fire()
    end,
    onAutoHarvest = function()
        if model:view(serverNow()).autoHarvestOwned then
            net.AutoHarvest.fire()
        else
            net.RequestPass.fire("AutoHarvest")
        end
    end,
    onExtraPlotsPass = function()
        net.RequestPass.fire("ExtraPlots")
    end,
}, GreenhouseData.cropIds())
redraw()

net.CoinsChanged.setCallback(function(coins)
    model:setCoins(coins)
    redraw()
end)
net.PlotChanged.setCallback(function(plot, crop, readyAt)
    model:setPlot(plot, crop, readyAt)
    redraw()
end)
net.StockChanged.setCallback(function(crop, seeds, produce)
    model:setStock(crop, seeds, produce)
    redraw()
end)
net.PassChanged.setCallback(function(extraPlots, autoHarvest)
    model:setPasses(extraPlots, autoHarvest)
    redraw()
end)

-- Countdowns tick on the server clock; once per second is enough for a seconds display.
local SECONDS_PER_REDRAW = 1
local sinceRedraw = 0
RunService.Heartbeat:Connect(function(deltaSeconds: number)
    sinceRedraw += deltaSeconds
    if sinceRedraw >= SECONDS_PER_REDRAW then
        sinceRedraw = 0
        redraw()
    end
end)

-- Parcels are built by the server (GreenhouseBuilder) with a ClickDetector and a "Plot" attribute.
-- The click is only an intent; the server decides whether it plants or harvests.
local function bindParcel(instance: Instance)
    local plot = instance:GetAttribute("Plot")
    local detector = instance:FindFirstChildOfClass("ClickDetector")
    if type(plot) ~= "number" or detector == nil then
        return
    end
    detector.MouseClick:Connect(function()
        local intent = model:intentForPlot(plot, serverNow())
        if intent == nil then
            return
        end
        if intent.kind == "plant" then
            local crop: CropName? = asCrop(intent.crop)
            if crop ~= nil then
                net.Plant.fire(plot, crop)
            end
        else
            net.Harvest.fire(plot)
        end
    end)
end

local world = Workspace:WaitForChild("GreenhouseWorld")
for _, child in world:GetChildren() do
    bindParcel(child)
end
world.ChildAdded:Connect(bindParcel)
