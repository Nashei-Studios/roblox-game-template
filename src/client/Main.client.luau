--!strict
--[[
    Client entry point. It mounts no UI: the template ships none (ADR 0071). The game UI system
    attaches at the "UI HOOK POINT" below through `GameUiBridge`. Never trust client input on the
    server: every remote below carries intent only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local AnnouncementPresenter = require(script.Parent.presenters.AnnouncementPresenter)
local ProgressRules = require(ReplicatedStorage.Shared.features.progress.ProgressRules)
local SoundManager = require(ReplicatedStorage.Shared.features.sound.SoundManager)
local ToastController = require(ReplicatedStorage.Shared.features.notifications.ToastController)
local net = require(ReplicatedStorage.Shared.net.generated.client)

local SetCoreToastRenderer = require(script.Parent.presenters.SetCoreToastRenderer)
local SoundEnginePresenter = require(script.Parent.presenters.SoundEnginePresenter)
local GameUiBridge = require(script.Parent.presenters.GameUiBridge)

-- TODO(game): the milestone text is the game's data; replace it with its own copy.
local ANNOUNCE_TEXT = "{name} reached {value}!"

print(`{Config.default.gameName} client started`)

-- UI HOOK POINT (ADR 0071). The template draws no UI: the game UI system attaches here and only
-- here. `mount` receives the actions (what its buttons call) and the content (products, gifts,
-- boards) and returns the listener it renders from (coins, shop rows, boards, volumes). Remotes,
-- prices and board replication stay behind GameUiBridge. Menu open/close state is
-- `features/ui/MenuController` over the `UiPresenter` port.
-- TODO(game): replace this empty mount with your UI, and write the copy of a shop row whose price
-- is still loading or cannot be read.
local uiListener = GameUiBridge.attach(
    function(_actions: GameUiBridge.Actions, _content: GameUiBridge.Content)
        return {}
    end,
    {
        shopPlaceholders = { pending = "...", unavailable = "-" },
    }
)

-- Server to client: the balance after a grant.
net.CoinsChanged.setCallback(function(coins)
    print(`Coins: {coins}`)
    local onCoins = uiListener.onCoins
    if onCoins ~= nil then
        onCoins(coins)
    end
end)

-- Engagement modules (ADR 0025): sound and toasts. The game UI calls net.RedeemCode.fire(text)
-- and, through `uiActions`, the daily reward, session gift, volume and community actions; the
-- server answers with toasts and volumes. Toasts use the SetCore renderer until the game UI
-- supplies its own `ToastRenderer`.
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

-- Milestone lines: the server sends the name and the value, the text is the game's data.
local announcements = AnnouncementPresenter.new({
    line = function(name: string, value: number): string
        return ProgressRules.format(ANNOUNCE_TEXT, name, value)
    end,
    display = function(text: string)
        local channels = TextChatService:FindFirstChild("TextChannels")
        local system = if channels ~= nil then channels:FindFirstChild("RBXSystem") else nil
        if system == nil or not system:IsA("TextChannel") then
            return
        end
        local shown, failure = pcall(function()
            system:DisplaySystemMessage(text)
        end)
        if not shown then
            warn(`Announcement failed: {failure}`)
        end
    end,
})
net.AnnounceMilestone.setCallback(function(name, value)
    announcements:receive(name, value)
end)

net.Notify.setCallback(function(kind, amount)
    toasts:receive(kind, amount, os.clock())
end)
net.SoundSettings.setCallback(function(music, sfx)
    soundManager:setVolumes({ music = music, sfx = sfx })
    local onVolumes = uiListener.onVolumes
    if onVolumes ~= nil then
        onVolumes(music, sfx)
    end
end)

RunService.Heartbeat:Connect(function(deltaSeconds: number)
    toasts:tick(os.clock())
    soundManager:step(deltaSeconds)
end)
