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
local NetTypes = require(Shared.net.generated.types)
-- Engagement modules (ADR 0025): requires.
local CodeRequests = require(Shared.features.codes.CodeRequests)
local Codes = require(Shared.features.codes.Codes)
local SoundRequests = require(Shared.features.sound.SoundRequests)
local SoundSettings = require(Shared.features.sound.SoundSettings)
local TimeRewardRequests = require(Shared.features.timerewards.TimeRewardRequests)
local TimeRewards = require(Shared.features.timerewards.TimeRewards)

local ProfileStore = require(ServerScriptService.Vendor.ProfileStore)

local AnalyticsServiceSink = require(script.Parent.adapters.AnalyticsServiceSink)
local ConfigServiceFlags = require(script.Parent.adapters.ConfigServiceFlags)
local MonetizationService = require(script.Parent.features.monetization.MonetizationService)
local PerfProbe = require(script.Parent.dev.PerfProbe)
local RemoteNotifier = require(script.Parent.adapters.RemoteNotifier)
local RemoteSoundPush = require(script.Parent.adapters.RemoteSoundPush)
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

-- Engagement modules (ADR 0025): promo codes, time rewards, notifications, sound.
-- Rewards use the existing ProductGrants path; every remote is rate-limited from PerfBudget.
local engagementPlayers = {
    GetPlayerByUserId = function(_self: unknown, userId: number): Player?
        return Players:GetPlayerByUserId(userId)
    end,
}
local function limiterFor(remote: string): RateLimiter.RateLimiter
    local limit = PerfBudget.clientRemotes[remote]
    return RateLimiter.new({
        capacity = limit.capacity,
        refillPerSecond = limit.refillPerSecond,
        clock = os.clock,
    })
end
local engagementLimiters: { [string]: RateLimiter.RateLimiter } = {
    RedeemCode = limiterFor("RedeemCode"),
    ClaimDailyReward = limiterFor("ClaimDailyReward"),
    ClaimSessionGift = limiterFor("ClaimSessionGift"),
    SetVolume = limiterFor("SetVolume"),
}
local notificationKinds: { [string]: boolean } = {}
for kind in Config.default.notifications.kinds do
    notificationKinds[kind] = true
end
local notifier = RemoteNotifier.new({
    players = engagementPlayers,
    kinds = notificationKinds,
    fire = function(player: Player, kind: string, amount: number)
        net.Notify.fire(player, kind :: NetTypes.NotificationKind, amount)
    end,
})
local soundPush = RemoteSoundPush.new({
    players = engagementPlayers,
    fire = function(player: Player, music: number, sfx: number)
        net.SoundSettings.fire(player, music, sfx)
    end,
})
local codes = Codes.new({
    config = Config.default.codes,
    now = os.time,
    profileFor = function(userId: number): PlayerData.PlayerData?
        return playerData:get(tostring(userId))
    end,
    grants = ProductGrants.new(Codes.grantTable(Config.default.codes)),
})
local timeRewards = TimeRewards.new({
    config = Config.default.timeRewards,
    now = os.time,
    profileFor = function(userId: number): PlayerData.PlayerData?
        return playerData:get(tostring(userId))
    end,
    grants = ProductGrants.new(TimeRewards.grantTable(Config.default.timeRewards)),
})
local soundSettings = SoundSettings.new({
    config = Config.default.sound,
    profileFor = function(userId: number): PlayerData.PlayerData?
        return playerData:get(tostring(userId))
    end,
    push = function(userId: number, volumes: { music: number, sfx: number })
        soundPush:push(userId, volumes)
    end,
})
local giftIds: { string } = {}
for _, gift in Config.default.timeRewards.sessionGifts do
    table.insert(giftIds, gift.id)
end
local codeRequests = CodeRequests.new({
    codes = codes,
    notifier = notifier,
    allow = function(userId: number): boolean
        return engagementLimiters.RedeemCode:allow(userId)
    end,
    maxCodeLength = Config.default.codes.maxCodeLength,
})
local timeRewardRequests = TimeRewardRequests.new({
    timeRewards = timeRewards,
    notifier = notifier,
    allowDaily = function(userId: number): boolean
        return engagementLimiters.ClaimDailyReward:allow(userId)
    end,
    allowSession = function(userId: number): boolean
        return engagementLimiters.ClaimSessionGift:allow(userId)
    end,
    giftIds = giftIds,
})
local soundRequests = SoundRequests.new({
    settings = soundSettings,
    allow = function(userId: number): boolean
        return engagementLimiters.SetVolume:allow(userId)
    end,
})
net.RedeemCode.setCallback(function(player: Player, code)
    codeRequests:handle(player.UserId, code)
end)
net.ClaimDailyReward.setCallback(function(player: Player)
    timeRewardRequests:handleDaily(player.UserId)
end)
net.ClaimSessionGift.setCallback(function(player: Player, giftId)
    timeRewardRequests:handleSession(player.UserId, giftId)
end)
net.SetVolume.setCallback(function(player: Player, group, percent)
    soundRequests:handle(player.UserId, group, percent)
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
    tracker:track("session_start", player.UserId, joined.value.sessionIndex)
    timeRewards:startSession(player.UserId)
    soundSettings:sendCurrent(player.UserId)
end)

Players.PlayerRemoving:Connect(function(player: Player)
    playerData:leave(tostring(player.UserId))
    purchaseLimiter:forget(player.UserId)
    codes:forget(player.UserId)
    timeRewards:forget(player.UserId)
    for _, limiter in engagementLimiters do
        limiter:forget(player.UserId)
    end
end)

PerfProbe.start(Config.default.perfProbeEnabled == true)

if flags:getBoolean("purchasesEnabled") then
    monetization.start()
end
