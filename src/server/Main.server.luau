--!strict
--[[
    The ONLY server Script: the composition root (ADR 0009). It builds adapters over engine
    services and ProfileStore, injects them into the feature services, and connects engine
    events. Game-specific wiring goes here; logic goes in features.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local ConfigService = game:GetService("ConfigService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local Analytics = require(Shared.features.analytics.Analytics)
local AnalyticsTracker = require(Shared.features.analytics.AnalyticsTracker)
local Clock = require(Shared.ports.Clock)
local Config = require(Shared.Config)
local Flags = require(Shared.features.flags.Flags)
local Funnel = require(Shared.features.greenhouse.Funnel)
local GreenhouseController = require(Shared.features.greenhouse.GreenhouseController)
local GreenhouseData = require(Shared.features.greenhouse.GreenhouseData)
local LedgerProvider = require(Shared.ports.LedgerProvider)
local Monetization = require(Shared.features.monetization.Monetization)
local PlayerData = require(Shared.features.playerdata.PlayerData)
local ProductGrants = require(Shared.features.monetization.ProductGrants)
local PlayerDataMigrations = require(Shared.features.playerdata.PlayerDataMigrations)
local PlayerDataService = require(Shared.features.playerdata.PlayerDataService)
local PurchaseRequests = require(Shared.features.monetization.PurchaseRequests)
local PerfBudget = require(Shared.perf.PerfBudget)
local RateLimiter = require(Shared.net.RateLimiter)
local net = require(Shared.net.generated.server)

local ProfileStore = require(ServerScriptService.Vendor.ProfileStore)

local AnalyticsServiceSink = require(script.Parent.adapters.AnalyticsServiceSink)
local ConfigServiceFlags = require(script.Parent.adapters.ConfigServiceFlags)
local MonetizationService = require(script.Parent.features.monetization.MonetizationService)
local GreenhouseBuilder = require(script.Parent.adapters.GreenhouseBuilder)
local PerfProbe = require(script.Parent.dev.PerfProbe)
local Validation = require(Shared.net.Validation)
local ProfileStoreRepository = require(script.Parent.adapters.ProfileStoreRepository)

-- Config is validated at boot; unset ids are reported, not hidden.
local problems = Config.validate(Config.default)
if #problems > 0 then
    warn(`Config is incomplete ({#problems} problem(s)):`)
    for _, problem in problems do
        warn(`  - {problem}`)
    end
end

ProfileStore.SetConstant("AUTO_SAVE_PERIOD", Config.default.autosaveIntervalSeconds)
ProfileStore.SetConstant("ASSUME_DEAD", Config.default.sessionLockTimeoutSeconds)

-- Adapters: the only code that touches engine services or ProfileStore.
local profileStore = ProfileStore.New("PlayerData", PlayerData.default())
local store: ProfileStoreRepository.StoreLike<PlayerData.PlayerData> = {
    StartSessionAsync = function(_self: unknown, profileKey: string, params: { Steal: boolean? }?)
        return profileStore:StartSessionAsync(profileKey, params or {})
    end,
}
local repository = ProfileStoreRepository.new(store, {
    clock = os.clock,
    wait = function(seconds: number)
        task.wait(seconds)
    end,
})
local flags = Flags.new(
    ConfigServiceFlags.new({
        configService = {
            GetConfigAsync = function(_self: unknown): ConfigServiceFlags.ConfigSnapshotLike
                return ConfigService:GetConfigAsync()
            end,
        },
    }),
    Config.flagDefaults
)

-- Feature services.
local tracker = AnalyticsTracker.new({
    sink = AnalyticsServiceSink.new({
        analytics = {
            LogCustomEvent = function(
                _self: unknown,
                player: Player,
                eventName: string,
                value: number
            )
                AnalyticsService:LogCustomEvent(player, eventName, value)
            end,
        },
        players = {
            GetPlayerByUserId = function(_self: unknown, userId: number): Player?
                return Players:GetPlayerByUserId(userId)
            end,
        },
    }),
    clock = function(): number
        return os.time()
    end,
    isValidEvent = Analytics.isFunnelEvent,
})

local playerData = PlayerDataService.new({
    repository = repository,
    onSessionLost = function(key: string)
        local player = Players:GetPlayerByUserId(tonumber(key) or 0)
        if player ~= nil then
            player:Kick("Your data session ended on another server. Please rejoin.")
        end
    end,
    -- Upgrade in place before anything reads the data (ADR 0014).
    migrate = function(data: PlayerData.PlayerData)
        return PlayerDataMigrations.migrateInPlace(data)
    end,
    startSession = function(data: PlayerData.PlayerData): number
        data.sessionCount += 1
        return data.sessionCount
    end,
})

-- Greenhouse (ADR 0020). Growth is measured by the server clock only; the client sends intent.
local serverClock: Clock.Clock = {
    now = function(_self: Clock.Clock): number
        return os.time()
    end,
}
-- One token bucket per remote, from the same numbers the bandwidth calculator reads (ADR 0019).
local limiters: { [string]: RateLimiter.RateLimiter } = {}
for remoteName, limit in PerfBudget.clientRemotes do
    limiters[remoteName] = RateLimiter.new({
        capacity = limit.capacity,
        refillPerSecond = limit.refillPerSecond,
        clock = os.clock,
    })
end
-- Pass ownership as the server read it from Roblox. Never filled from a client message.
local ownedPasses: { [number]: { [string]: boolean } } = {}
local greenhouse = GreenhouseController.new({
    clock = serverClock,
    dataFor = function(userId: number): PlayerData.PlayerData?
        return playerData:get(tostring(userId))
    end,
    allow = function(userId: number, remote: string): boolean
        local limiter = limiters[remote]
        return limiter ~= nil and limiter:allow(userId)
    end,
    ownsPass = function(userId: number, passName: string): boolean
        local owned = ownedPasses[userId]
        return owned ~= nil and owned[passName] == true
    end,
    funnel = Funnel.new({
        track = function(name: string, userId: number, sessionIndex: number): boolean
            return tracker:track(name, userId, sessionIndex)
        end,
    }),
})

local ledgers: LedgerProvider.LedgerProvider = {
    ledgerFor = function(
        _self: LedgerProvider.LedgerProvider,
        userId: number
    ): LedgerProvider.ReceiptLedger?
        local data = playerData:get(tostring(userId))
        if data == nil then
            return nil
        end
        return Monetization.newListLedger(data.purchaseIds, Config.default.purchaseLedgerSize)
    end,
}

local productGrants = ProductGrants.new(Config.grantsByName(Config.default))

local monetization = MonetizationService.new({
    ledgers = ledgers,
    -- Roblox is told the purchase was granted only after the data holding its PurchaseId is
    -- confirmed saved (ADR 0016).
    confirmSaved = function(userId: number, purchaseId: string): boolean
        local confirmed = playerData:confirmSaved(
            tostring(userId),
            function(saved: PlayerData.PlayerData): boolean
                return table.find(saved.purchaseIds, purchaseId) ~= nil
            end,
            Config.default.saveConfirmTimeoutSeconds
        )
        return confirmed.ok
    end,
    -- True only when the product was delivered; a failed grant is not recorded, so Roblox
    -- retries the receipt (see Monetization.processReceipt).
    grant = function(receipt: Monetization.ReceiptInfo): boolean
        local product = Config.findProductById(Config.default, receipt.productId)
        if product == nil then
            warn(`Receipt for unknown product id {receipt.productId}`)
            return false
        end
        local data = playerData:get(tostring(receipt.playerId))
        if data == nil then
            return false
        end
        local applied = productGrants:apply(data, product.name)
        if not applied.ok then
            warn(`Could not grant "{product.name}": {applied.error.kind}`)
            return false
        end
        -- Coins and seeds reach the client with the next state flush (the wire clamps coins to u32).
        greenhouse:markDirty(receipt.playerId)
        return true
    end,
})

-- Remotes (ADR 0012, ADR 0015): the generated layer decodes, PurchaseRequests rate-limits and
-- validates, and only then is the purchase prompt opened.
-- The limit lives in PerfBudget so the static bandwidth calculator reads the same numbers (ADR 0019).
local purchaseLimit = PerfBudget.clientRemotes.RequestPurchase
local purchaseLimiter = RateLimiter.new({
    capacity = purchaseLimit.capacity,
    refillPerSecond = purchaseLimit.refillPerSecond,
    clock = os.clock,
})
local purchaseNames: { string } = {}
for _, product in Config.default.developerProducts do
    table.insert(purchaseNames, product.name)
end
local purchaseRequests = PurchaseRequests.new({
    productNames = purchaseNames,
    allow = function(userId: number): boolean
        return purchaseLimiter:allow(userId)
    end,
    prompt = function(userId: number, productName: string): boolean
        local player = Players:GetPlayerByUserId(userId)
        local product = Config.findProductByName(Config.default, productName)
        if player == nil or product == nil or product.id == nil then
            return false
        end
        MarketplaceService:PromptProductPurchase(player, product.id)
        return true
    end,
})
net.RequestPurchase.setCallback(function(player: Player, product)
    local handled = purchaseRequests:handle(player.UserId, product)
    if not handled.ok then
        warn(`RequestPurchase from {player.UserId} dropped: {handled.reason}`)
    end
end)

-- Greenhouse remotes: the controller rate-limits, validates and applies the rule on the server.
local function logRefusal(remote: string, userId: number, result: GreenhouseController.HandleResult)
    if not result.ok then
        warn(`{remote} from {userId} refused: {result.reason}`)
    end
end

net.Plant.setCallback(function(player: Player, plot, crop)
    logRefusal("Plant", player.UserId, greenhouse:plant(player.UserId, plot, crop))
end)
net.Harvest.setCallback(function(player: Player, plot)
    logRefusal("Harvest", player.UserId, greenhouse:harvest(player.UserId, plot))
end)
net.Sell.setCallback(function(player: Player)
    logRefusal("Sell", player.UserId, greenhouse:sell(player.UserId))
end)
net.BuyPlot.setCallback(function(player: Player)
    logRefusal("BuyPlot", player.UserId, greenhouse:buyPlot(player.UserId))
end)
net.BuySeed.setCallback(function(player: Player, crop)
    logRefusal("BuySeed", player.UserId, greenhouse:buySeed(player.UserId, crop))
end)
net.AutoHarvest.setCallback(function(player: Player)
    logRefusal("AutoHarvest", player.UserId, greenhouse:autoHarvest(player.UserId))
end)

-- Passes: ownership is read from Roblox at join and after the purchase prompt, never from the client.
local function findPass(name: string): Config.ProductConfig?
    for _, pass in Config.default.gamePasses do
        if pass.name == name then
            return pass
        end
    end
    return nil
end

local function refreshPasses(player: Player)
    local owned: { [string]: boolean } = {}
    for _, pass in Config.default.gamePasses do
        local passId = pass.id
        if passId ~= nil then
            local ok, owns = pcall(function(): boolean
                return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
            end)
            if ok then
                owned[pass.name] = owns
            else
                warn(`Could not read pass "{pass.name}" ownership for {player.UserId}: {owns}`)
            end
        end
    end
    ownedPasses[player.UserId] = owned
    greenhouse:passesChanged(player.UserId)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(
    function(player: Player, passId: number, wasPurchased: boolean)
        if not wasPurchased then
            return
        end
        for _, pass in Config.default.gamePasses do
            if pass.id == passId then
                local owned = ownedPasses[player.UserId] or {}
                owned[pass.name] = true
                ownedPasses[player.UserId] = owned
                greenhouse:passesChanged(player.UserId)
            end
        end
    end
)

net.RequestPass.setCallback(function(player: Player, pass)
    local limiter = limiters.RequestPass
    if limiter == nil or not limiter:allow(player.UserId) then
        return
    end
    local checked = Validation.oneOf(
        pass,
        { GreenhouseData.PASS_EXTRA_PLOTS, GreenhouseData.PASS_AUTO_HARVEST }
    )
    local config = if checked.ok then findPass(checked.value) else nil
    if config == nil or config.id == nil then
        warn(`RequestPass from {player.UserId} dropped: unknown pass or no id configured`)
        return
    end
    MarketplaceService:PromptGamePassPurchase(player, config.id)
end)

-- Engine events.
Players.PlayerAdded:Connect(function(player: Player)
    local joined = playerData:join(tostring(player.UserId))
    if not joined.ok then
        local failure = joined.error
        warn(
            `Could not load data for {player.UserId}: {if type(failure) == "string"
                then failure
                else failure.kind}`
        )
        player:Kick("Could not load your data. Please rejoin.")
        return
    end
    refreshPasses(player)
    -- session_start (and the tutorial events) come from the greenhouse funnel.
    greenhouse:join(player.UserId, joined.value.sessionIndex)
end)

Players.PlayerRemoving:Connect(function(player: Player)
    playerData:leave(tostring(player.UserId))
    purchaseLimiter:forget(player.UserId)
    for _, limiter in limiters do
        limiter:forget(player.UserId)
    end
    greenhouse:leave(player.UserId)
    ownedPasses[player.UserId] = nil
end)

-- State sync: dirty plots and stock go out at most twice a second per player (PerfBudget).
local FLUSH_INTERVAL_SECONDS = 0.5
task.spawn(function()
    while true do
        task.wait(FLUSH_INTERVAL_SECONDS)
        for _, player in Players:GetPlayers() do
            greenhouse:flush(player.UserId, {
                plot = function(plot: number, cropIndex: number, readyAt: number)
                    net.PlotChanged.fire(player, plot, cropIndex, readyAt)
                end,
                stock = function(cropIndex: number, seeds: number, produce: number)
                    net.StockChanged.fire(player, cropIndex, seeds, produce)
                end,
                coins = function(coins: number)
                    net.CoinsChanged.fire(player, coins)
                end,
                passes = function(extraPlots: boolean, autoHarvest: boolean)
                    net.PassChanged.fire(player, extraPlots, autoHarvest)
                end,
            })
        end
    end
end)

GreenhouseBuilder.new():build()

PerfProbe.start(Config.default.perfProbeEnabled == true)

if flags:getBoolean("purchasesEnabled") then
    monetization.start()
end
