--!strict
--[[
    Client entry point (ADR 0021). Thin adapter: it sends intent (cast, reel, sell, buy a rod) and
    draws what HudModel returns. It owns no rules and trusts nothing it computes: the catch, the
    coins, the bucket and the rod level shown here are server values. UI beyond this minimal HUD is
    built in Studio (partially managed Rojo).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local HudModel = require(Shared.features.reef.HudModel)
local ReefConfig = require(Shared.features.reef.ReefConfig)
local net = require(Shared.net.generated.client)

local ReefHud = require(script.Parent.ReefHud)

print(`{Config.default.gameName} client started`)

local model = HudModel.new(ReefConfig.default)
local rodLevel = 1
local hud: ReefHud.ReefHud

local function redraw()
    hud:render(model:view())
end

hud = ReefHud.new({
    onCast = function()
        -- Intent only: the deepest zone this rod reaches. The server checks it again.
        local rod = ReefConfig.rod(ReefConfig.default, rodLevel)
        net.Cast.fire(if rod == nil then 1 else rod.maxZone)
        model:castStarted()
        redraw()
    end,
    onReel = function()
        net.Reel.fire()
    end,
    onSell = function()
        net.Sell.fire()
    end,
    onBuyRod = function()
        net.BuyRod.fire()
    end,
})
redraw()

net.CoinsChanged.setCallback(function(coins)
    model:setCoins(coins)
    redraw()
end)
net.RodChanged.setCallback(function(newRodLevel)
    rodLevel = newRodLevel
    model:setRod(newRodLevel)
    redraw()
end)
net.StockChanged.setCallback(function(count, capacity)
    model:setStock(count, capacity)
    redraw()
end)
net.Bite.setCallback(function()
    model:bite()
    redraw()
end)
net.CatchResult.setCallback(function(fish)
    model:catchResult(fish)
    redraw()
end)
