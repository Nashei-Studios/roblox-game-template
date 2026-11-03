--!strict
--[[
    Client entry point (ADR 0020). Thin adapter: it reads input, batches key presses, sends
    intent to the server and draws what HudModel returns. It owns no rules and trusts nothing it
    computes: the multiplier, coins and progress shown here are server values.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local HudModel = require(Shared.features.keysprint.HudModel)
local KeySprintRules = require(Shared.features.keysprint.KeySprintRules)
local PressBatcher = require(Shared.features.keysprint.PressBatcher)
local net = require(Shared.net.generated.client)

local KeySprintHud = require(script.Parent.KeySprintHud)

print(`{Config.default.gameName} client started`)

-- One PressBatch per window keeps the client inside the remote budget (ADR 0019).
local BATCH_INTERVAL_SECONDS = 0.25

local model = HudModel.new()
local batcher = PressBatcher.new(BATCH_INTERVAL_SECONDS)

local hud = KeySprintHud.new({
    onUpgrade = function()
        net.BuyCap.fire()
    end,
    onSkip = function()
        net.SkipStage.fire()
    end,
})
local function redraw()
    hud:render(model:view())
end
redraw()

net.CoinsChanged.setCallback(function(coins)
    model:setCoins(coins)
    redraw()
end)
net.MultiplierChanged.setCallback(function(multiplier, multiplierCap)
    model:setMultiplier(multiplier, multiplierCap)
    redraw()
end)
net.ProgressChanged.setCallback(function(highestStage, multiplierCap)
    model:setProgress(highestStage, multiplierCap)
    redraw()
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
    if processed or input.KeyCode.Name ~= KeySprintRules.PRESS_KEY_NAME then
        return
    end
    batcher:press()
    model:notePress()
    redraw()
end)

RunService.Heartbeat:Connect(function()
    local count = batcher:flush(os.clock())
    if count > 0 then
        net.PressBatch.fire(count)
    end
end)

-- Finish pads carry the attribute "Stage"; the server decides whether the touch counts.
local lastFinishReport = 0
local function onCharacter(character: Model)
    local root = character:WaitForChild("HumanoidRootPart") :: BasePart
    root.Touched:Connect(function(other: BasePart)
        local stage = other:GetAttribute("Stage")
        if other.Name ~= "Finish" or type(stage) ~= "number" then
            return
        end
        if os.clock() - lastFinishReport < 1 then
            return
        end
        lastFinishReport = os.clock()
        net.Finish.fire(stage)
    end)
end

local player = Players.LocalPlayer
if player.Character ~= nil then
    task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)

-- Referenced so the stage folder replicates before the first touch.
Workspace:WaitForChild("KeySprintStages")
