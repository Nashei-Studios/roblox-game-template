--!strict
--[[
    Client entry point. UI is built in Studio (partially managed Rojo); this script
    only binds behavior to it. Never trust client input on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local SoundManager = require(ReplicatedStorage.Shared.features.sound.SoundManager)
local ToastController = require(ReplicatedStorage.Shared.features.notifications.ToastController)
local net = require(ReplicatedStorage.Shared.net.generated.client)

local SetCoreToastRenderer = require(script.Parent.presenters.SetCoreToastRenderer)
local SoundEnginePresenter = require(script.Parent.presenters.SoundEnginePresenter)

print(`{Config.default.gameName} client started`)

-- Server to client: the balance after a grant. Bind it to the UI built in Studio.
net.CoinsChanged.setCallback(function(coins)
    print(`Coins: {coins}`)
end)

-- Engagement modules (ADR 0025): sound and toasts. The Studio-built UI calls
-- net.RedeemCode.fire(text), net.ClaimDailyReward.fire(), net.ClaimSessionGift.fire(giftId) and
-- net.SetVolume.fire(group, percent); the server answers with toasts (Notify) and volumes.
local soundManager = SoundManager.new({
    config = Config.default.sound,
    engine = SoundEnginePresenter.new(),
    volumes = {
        music = Config.default.sound.defaultVolumes.music,
        sfx = Config.default.sound.defaultVolumes.sfx,
    },
})
local toasts = ToastController.new({
    config = Config.default.notifications,
    renderer = SetCoreToastRenderer.new(),
    playSound = function(name: string)
        soundManager:playSfx(name)
    end,
})

net.Notify.setCallback(function(kind, amount)
    toasts:receive(kind, amount, os.clock())
end)
net.SoundSettings.setCallback(function(music, sfx)
    soundManager:setVolumes({ music = music, sfx = sfx })
end)

RunService.Heartbeat:Connect(function(deltaSeconds: number)
    toasts:tick(os.clock())
    soundManager:step(deltaSeconds)
end)
