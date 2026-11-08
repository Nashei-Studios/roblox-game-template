--!strict
--[[
    Client entry point. It mounts the UI kit (src/client/presenters/ui) from Config.default.ui and
    binds the remotes to its buttons; a game restyles it through Config tokens, not by editing
    presenters. Never trust client input on the server: every remote below carries intent only.
]]

local GroupService = game:GetService("GroupService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local LeaderboardsConfig =
    require(ReplicatedStorage.Shared.features.leaderboards.LeaderboardsConfig)
local NetTypes = require(ReplicatedStorage.Shared.net.generated.types)
local ShopModel = require(ReplicatedStorage.Shared.features.ui.ShopModel)
local SoundManager = require(ReplicatedStorage.Shared.features.sound.SoundManager)
local ToastController = require(ReplicatedStorage.Shared.features.notifications.ToastController)
local net = require(ReplicatedStorage.Shared.net.generated.client)

local SetCoreToastRenderer = require(script.Parent.presenters.SetCoreToastRenderer)
local AnnouncerDisplay = require(script.Parent.presenters.AnnouncerDisplay)
local SoundEnginePresenter = require(script.Parent.presenters.SoundEnginePresenter)
local UiKit = require(script.Parent.presenters.ui.UiKit)
local UiToastRenderer = require(script.Parent.presenters.ui.UiToastRenderer)

print(`{Config.default.gameName} client started`)

-- UI kit (issue #23): HUD, shop, rewards, settings, leaderboards and the toast host, all from
-- Config.default.ui. Without it the SetCore debug toast is the fallback.
local uiConfig = Config.default.ui
local kit: UiKit.UiKit? = nil
if uiConfig ~= nil then
    local localPlayer = Players.LocalPlayer
    local nameCache: { [number]: string } = {}
    local community = Config.default.communityReward
    local boards = Config.default.leaderboards
    local giftIds: { string } = {}
    for _, gift in Config.default.timeRewards.sessionGifts do
        table.insert(giftIds, gift.id)
    end
    local shopProducts: { ShopModel.Product } = {}
    for _, product in Config.default.developerProducts do
        table.insert(shopProducts, { name = product.name, id = product.id })
    end
    local showCard = community ~= nil
        and community.enabled
        and community.promptJoin
        and community.communityId ~= nil
    local mounted = UiKit.new({
        playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui,
        camera = workspace.CurrentCamera,
        config = uiConfig,
        content = {
            products = shopProducts,
            giftIds = giftIds,
            boardIds = if boards ~= nil then LeaderboardsConfig.sortedIds(boards) else {},
            showCommunityCard = showCard,
        },
        actions = {
            buy = function(productName: string)
                net.RequestPurchase.fire(productName :: NetTypes.ProductName)
            end,
            claimDaily = function()
                net.ClaimDailyReward.fire()
            end,
            claimGift = function(giftId: string)
                net.ClaimSessionGift.fire(giftId)
            end,
            joinCommunity = function()
                local communityId = if community ~= nil then community.communityId else nil
                if communityId == nil then
                    return
                end
                local prompted, failure = pcall(function()
                    GroupService:PromptJoinAsync(communityId)
                end)
                if not prompted then
                    warn(`Join prompt failed: {failure}`)
                end
            end,
            checkCommunity = function()
                net.RequestCommunityCheck.fire()
            end,
            setVolume = function(group: "music" | "sfx", percent: number)
                net.SetVolume.fire(group, percent)
            end,
        },
        nameOf = function(userId: number): string?
            local cached = nameCache[userId]
            if cached ~= nil then
                return cached
            end
            local found, name = pcall(function()
                return Players:GetNameFromUserIdAsync(userId)
            end)
            if not found then
                warn(`Could not resolve the name of {userId}: {name}`)
                return nil
            end
            nameCache[userId] = name
            return name
        end,
    })
    kit = mounted

    -- Shop prices are read at runtime for this player (Plus and regional prices differ).
    local states: { [string]: ShopModel.QuoteState } = {}
    local function refreshShop()
        mounted:setShopRows(ShopModel.rows(shopProducts, states, {
            pending = uiConfig.strings.pricePending,
            unavailable = uiConfig.strings.priceUnavailable,
        }))
    end
    refreshShop()
    for _, product in shopProducts do
        local productId = product.id
        if productId ~= nil then
            task.spawn(function()
                local read, info = pcall(function()
                    return MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product)
                end)
                local robux: number? = if read then info.PriceInRobux else nil
                if robux == nil then
                    states[product.name] = { status = "failed" }
                    warn(`Price of "{product.name}" could not be read`)
                else
                    states[product.name] = {
                        status = "ready",
                        quote = ShopModel.quoteFromPrices(robux, nil),
                    }
                end
                refreshShop()
            end)
        end
    end

    -- Leaderboards arrive as replicated values (server to client only); no remote is involved.
    local boardsFolder = ReplicatedStorage:WaitForChild("Boards", 10)
    if boardsFolder ~= nil then
        local function bind(value: Instance)
            if value:IsA("StringValue") then
                mounted:setBoard(value.Name, value.Value)
                value:GetPropertyChangedSignal("Value"):Connect(function()
                    mounted:setBoard(value.Name, value.Value)
                end)
            end
        end
        for _, existing in boardsFolder:GetChildren() do
            bind(existing)
        end
        boardsFolder.ChildAdded:Connect(bind)
    else
        warn("Boards folder did not replicate; leaderboards stay empty")
    end
end

-- Server to client: one announcer line (DisplaySystemMessage is client-only).
net.AnnouncerLine.setCallback(AnnouncerDisplay.show)

-- Server to client: the balance after a grant.
net.CoinsChanged.setCallback(function(coins)
    print(`Coins: {coins}`)
    local mounted = kit
    local ui = Config.default.ui
    if mounted ~= nil and ui ~= nil then
        mounted.presenter:setText("hud.coins", `{ui.strings.coinsLabel}: {coins}`)
    end
end)

-- Engagement modules (ADR 0025): sound and toasts. The kit calls net.RedeemCode.fire(text),
-- net.ClaimDailyReward.fire(), net.ClaimSessionGift.fire(giftId), net.SetVolume.fire(group,
-- percent) and net.RequestCommunityCheck.fire(); the server answers with toasts and volumes.
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
    renderer = if kit ~= nil and uiConfig ~= nil
        then UiToastRenderer.new(kit.gui, uiConfig)
        else SetCoreToastRenderer.new(),
    playSound = function(name: string)
        soundManager:playSfx(name)
    end,
})

net.Notify.setCallback(function(kind, amount)
    toasts:receive(kind, amount, os.clock())
end)
net.SoundSettings.setCallback(function(music, sfx)
    soundManager:setVolumes({ music = music, sfx = sfx })
    local mounted = kit
    if mounted ~= nil then
        mounted:setVolumes(music, sfx)
    end
end)

RunService.Heartbeat:Connect(function(deltaSeconds: number)
    toasts:tick(os.clock())
    soundManager:step(deltaSeconds)
end)
