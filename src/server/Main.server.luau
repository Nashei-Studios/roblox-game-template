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
local Config = require(Shared.Config)
local Flags = require(Shared.features.flags.Flags)
local FishWire = require(Shared.features.reef.FishWire)
local LedgerProvider = require(Shared.ports.LedgerProvider)
local Monetization = require(Shared.features.monetization.Monetization)
local PlayerData = require(Shared.features.playerdata.PlayerData)
local ProductGrants = require(Shared.features.monetization.ProductGrants)
local PlayerDataMigrations = require(Shared.features.playerdata.PlayerDataMigrations)
local PlayerDataService = require(Shared.features.playerdata.PlayerDataService)
local PurchaseRequests = require(Shared.features.monetization.PurchaseRequests)
local PerfBudget = require(Shared.perf.PerfBudget)
local ReefConfig = require(Shared.features.reef.ReefConfig)
local ReefController = require(Shared.features.reef.ReefController)
local ReefFunnel = require(Shared.features.reef.Funnel)
local ReefRules = require(Shared.features.reef.ReefRules)
local RateLimiter = require(Shared.net.RateLimiter)
local net = require(Shared.net.generated.server)

local ProfileStore = require(ServerScriptService.Vendor.ProfileStore)

local AnalyticsServiceSink = require(script.Parent.adapters.AnalyticsServiceSink)
local ConfigServiceFlags = require(script.Parent.adapters.ConfigServiceFlags)
local MonetizationService = require(script.Parent.features.monetization.MonetizationService)
local PerfProbe = require(script.Parent.dev.PerfProbe)
local ProfileStoreRepository = require(script.Parent.adapters.ProfileStoreRepository)
local SellStand = require(script.Parent.adapters.SellStand)

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

-- Largest value the CoinsChanged remote (u32 in net/schema.zap) can carry.
local MAX_WIRE_COINS = 4294967295

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
        local player = Players:GetPlayerByUserId(receipt.playerId)
        if player ~= nil then
            -- The wire type is u32: clamp instead of letting a large balance fail the send.
            net.CoinsChanged.fire(player, math.min(data.coins, MAX_WIRE_COINS))
        end
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

-- Reef (ADR 0021). The client sends intent; ReefController owns the catch, the prices and the coins.
local ownedPasses: { [number]: { [string]: boolean } } = {}
local sellStand = SellStand.new(ReefRules.STAND_RANGE)
local random = Random.new()

local reef = ReefController.new({
    table = ReefConfig.default,
    clock = os.clock,
    rng = function(): number
        return random:NextNumber()
    end,
    ownsPass = function(userId: number, passName: string): boolean
        local owned = ownedPasses[userId]
        return owned ~= nil and owned[passName] == true
    end,
    isNearStand = function(userId: number): boolean
        return sellStand:isNear(userId)
    end,
})
local reefFunnel = ReefFunnel.new({
    track = function(name: string, userId: number, sessionIndex: number): boolean
        return tracker:track(name, userId, sessionIndex)
    end,
})

local function limiterFor(remoteName: string): RateLimiter.RateLimiter
    local limit = PerfBudget.clientRemotes[remoteName]
    return RateLimiter.new({
        capacity = limit.capacity,
        refillPerSecond = limit.refillPerSecond,
        clock = os.clock,
    })
end
local castLimiter = limiterFor("Cast")
local reelLimiter = limiterFor("Reel")
local sellLimiter = limiterFor("Sell")
local buyRodLimiter = limiterFor("BuyRod")

local function pushCoins(player: Player, data: PlayerData.PlayerData)
    net.CoinsChanged.fire(player, math.min(data.coins, MAX_WIRE_COINS))
end

local function pushStock(player: Player, data: PlayerData.PlayerData)
    local capacity = reef:bucketCapacity(player.UserId)
    net.StockChanged.fire(player, math.min(reef:stockCount(data), 255), math.min(capacity, 255))
end

local function pushState(player: Player, data: PlayerData.PlayerData)
    pushCoins(player, data)
    pushStock(player, data)
    net.RodChanged.fire(player, math.min(data.rodLevel, 255))
end

local function playerDataOf(userId: number): PlayerData.PlayerData?
    return playerData:get(tostring(userId))
end

net.Cast.setCallback(function(player: Player, zone)
    local userId = player.UserId
    local data = playerDataOf(userId)
    if data == nil or not castLimiter:allow(userId) then
        return
    end
    local cast = reef:cast(userId, data, zone)
    if not cast.ok then
        warn(`Cast from {userId} dropped: {cast.error.kind}`)
        -- Tell the client the line is not out, so its HUD returns to idle.
        net.CatchResult.fire(player, nil)
        if cast.error.kind == "bucket_full" then
            pushStock(player, data)
        end
        return
    end
    reefFunnel:onCastAccepted(userId)
    local castId = cast.value.castId
    -- The bite time never leaves the server; the client is told only when to reel.
    task.delay(cast.value.biteDelaySeconds, function()
        if player.Parent ~= nil and reef:isPending(userId, castId) then
            net.Bite.fire(player)
        end
    end)
end)

net.Reel.setCallback(function(player: Player)
    local userId = player.UserId
    local data = playerDataOf(userId)
    if data == nil or not reelLimiter:allow(userId) then
        return
    end
    local reeled = reef:reel(userId, data)
    if not reeled.ok then
        warn(`Reel from {userId} dropped: {reeled.error.kind}`)
        net.CatchResult.fire(player, nil)
        return
    end
    if reeled.value.caught then
        net.CatchResult.fire(player, FishWire.toWire(reeled.value.fishId))
        pushStock(player, data)
    else
        net.CatchResult.fire(player, nil)
    end
end)

net.Sell.setCallback(function(player: Player)
    local userId = player.UserId
    local data = playerDataOf(userId)
    if data == nil or not sellLimiter:allow(userId) then
        return
    end
    local sold = reef:sell(userId, data)
    if not sold.ok then
        warn(`Sell from {userId} dropped: {sold.error.kind}`)
        return
    end
    pushCoins(player, data)
    pushStock(player, data)
end)

net.BuyRod.setCallback(function(player: Player)
    local userId = player.UserId
    local data = playerDataOf(userId)
    if data == nil or not buyRodLimiter:allow(userId) then
        return
    end
    local bought = reef:buyRod(userId, data)
    if not bought.ok then
        warn(`BuyRod from {userId} dropped: {bought.error.kind}`)
        return
    end
    reefFunnel:onRodBought(userId)
    pushState(player, data)
end)

-- Passes: ownership is read from Roblox at join and when a purchase finishes, never from the client.
local function refreshPasses(player: Player)
    for _, pass in Config.default.gamePasses do
        local passId = pass.id
        if passId == nil then
            continue
        end
        local ok, owns = pcall(function(): boolean
            return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
        end)
        if ok then
            local owned = ownedPasses[player.UserId] or {}
            owned[pass.name] = owns
            ownedPasses[player.UserId] = owned
        else
            warn(`Could not read pass "{pass.name}" ownership for {player.UserId}: {owns}`)
        end
    end
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
                local data = playerDataOf(player.UserId)
                if data ~= nil then
                    pushStock(player, data)
                end
            end
        end
    end
)

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
    -- session_start and the tutorial events come from the Reef funnel (Funnel).
    reefFunnel:onJoin(player.UserId, joined.value.sessionIndex, joined.value.data.totalCatches)
    refreshPasses(player)
    pushState(player, joined.value.data)
end)

Players.PlayerRemoving:Connect(function(player: Player)
    playerData:leave(tostring(player.UserId))
    purchaseLimiter:forget(player.UserId)
    castLimiter:forget(player.UserId)
    reelLimiter:forget(player.UserId)
    sellLimiter:forget(player.UserId)
    buyRodLimiter:forget(player.UserId)
    reef:forget(player.UserId)
    reefFunnel:forget(player.UserId)
    ownedPasses[player.UserId] = nil
end)

PerfProbe.start(Config.default.perfProbeEnabled == true)

if flags:getBoolean("purchasesEnabled") then
    monetization.start()
end
