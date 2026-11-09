--!strict
--[[
    The ONLY server Script: the composition root (ADR 0009). It builds adapters over engine
    services and ProfileStore, injects them into the feature services, and connects engine
    events. Game-specific wiring goes here; logic goes in features.
]]

local AdService = game:GetService("AdService")
local AnalyticsService = game:GetService("AnalyticsService")
local ConfigService = game:GetService("ConfigService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage.Shared
local Analytics = require(Shared.features.analytics.Analytics)
local AnalyticsTracker = require(Shared.features.analytics.AnalyticsTracker)
local BenefitReconciler = require(Shared.features.subscriptions.BenefitReconciler)
local Config = require(Shared.Config)
local Flags = require(Shared.features.flags.Flags)
local LedgerProvider = require(Shared.ports.LedgerProvider)
local Monetization = require(Shared.features.monetization.Monetization)
local PlayerData = require(Shared.features.playerdata.PlayerData)
local ProductGrants = require(Shared.features.monetization.ProductGrants)
local PlayerDataMigrations = require(Shared.features.playerdata.PlayerDataMigrations)
local PlayerDataService = require(Shared.features.playerdata.PlayerDataService)
local PlusPrompt = require(Shared.features.plus.PlusPrompt)
local PrivateServer = require(Shared.features.privateserver.PrivateServer)
local PurchaseRequests = require(Shared.features.monetization.PurchaseRequests)
local PerfBudget = require(Shared.perf.PerfBudget)
local RateLimiter = require(Shared.net.RateLimiter)
local RewardedAds = require(Shared.features.rewardedads.RewardedAds)
local RobuxTransfers = require(Shared.features.robuxtransfers.RobuxTransfers)
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
local ProfileStoreRepository = require(script.Parent.adapters.ProfileStoreRepository)
local RemoteNotifier = require(script.Parent.adapters.RemoteNotifier)
local RemoteSoundPush = require(script.Parent.adapters.RemoteSoundPush)
local CommunityReward = require(Shared.features["community-reward"].CommunityReward)
local CommunityRewardRequests = require(Shared.features["community-reward"].CommunityRewardRequests)
local BoardKey = require(Shared.features.leaderboards.BoardKey)
local Leaderboards = require(Shared.features.leaderboards.Leaderboards)
local LeaderboardsPort = require(Shared.ports.Leaderboards)
local OrderedDataStoreBoards = require(script.Parent.adapters.OrderedDataStoreBoards)
local ReplicatedBoardPublisher = require(script.Parent.adapters.ReplicatedBoardPublisher)
local RobloxGroupMembership = require(script.Parent.adapters.RobloxGroupMembership)
local RobloxLeaderstats = require(script.Parent.adapters.RobloxLeaderstats)
local RobloxAdService = require(script.Parent.adapters.RobloxAdService)
local RobloxMarketplaceSubscriptions =
    require(script.Parent.adapters.RobloxMarketplaceSubscriptions)
local RobloxPlusSubscription = require(script.Parent.adapters.RobloxPlusSubscription)
local RobloxRobuxTransfers = require(script.Parent.adapters.RobloxRobuxTransfers)
local RobloxServerContext = require(script.Parent.adapters.RobloxServerContext)

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
}, function(data: PlayerData.PlayerData): { ok: boolean }
    -- Migrate the raw record before Reconcile fills template keys into it.
    local migrated = PlayerDataMigrations.migrateInPlace(data)
    local ok: boolean = migrated.ok
    return { ok = ok }
end)
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
        -- The grant is done. Anything that fails from here on must not abort the receipt before it
        -- is recorded, or Roblox would retry it and deliver the product a second time.
        local told, failure = pcall(function()
            local player = Players:GetPlayerByUserId(receipt.playerId)
            if player ~= nil then
                -- The wire type is u32: clamp instead of letting a large balance fail the send.
                net.CoinsChanged.fire(player, math.min(data.coins, MAX_WIRE_COINS))
            end
        end)
        if not told then
            warn(`Purchase of "{product.name}" delivered, but telling the client failed: {failure}`)
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

-- Monetization surfaces (ADR 0022). Each module sits behind a port; these are the engine
-- adapters and the only place they are chosen. A pack adapter would replace one line here.
local remoteLimiters: { RateLimiter.RateLimiter } = {}
local function limiterFor(remoteName: string): RateLimiter.RateLimiter
    local limit = PerfBudget.clientRemotes[remoteName]
    local limiter = RateLimiter.new({
        capacity = limit.capacity,
        refillPerSecond = limit.refillPerSecond,
        clock = os.clock,
    })
    table.insert(remoteLimiters, limiter)
    return limiter
end

local function playerById(userId: number): Player?
    return Players:GetPlayerByUserId(userId)
end

-- Experience subscriptions: benefits follow the LIVE status (join, change event and a poll,
-- because the engine fires the event only after the purchase modal closes).
local subscriptionEntries = BenefitReconciler.entriesFromConfig(Config.default)
local reconciler = BenefitReconciler.new({
    entries = subscriptionEntries,
    port = RobloxMarketplaceSubscriptions.new({
        marketplace = {
            GetUserSubscriptionStatusAsync = function(
                _self: unknown,
                player: Player,
                subscriptionId: string
            ): RobloxMarketplaceSubscriptions.StatusLike
                local status =
                    MarketplaceService:GetUserSubscriptionStatusAsync(player, subscriptionId)
                return { IsSubscribed = status.IsSubscribed == true }
            end,
            UserOwnsGamePassAsync = function(
                _self: unknown,
                userId: number,
                passId: number
            ): boolean
                return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
            end,
        },
        players = {
            GetPlayerByUserId = function(_self: unknown, userId: number): Player?
                return playerById(userId)
            end,
            ConnectStatusChanged = function(
                _self: unknown,
                listener: (player: Player, subscriptionId: string) -> ()
            ): () -> ()
                local connection = Players.UserSubscriptionStatusChanged:Connect(listener)
                return function()
                    connection:Disconnect()
                end
            end,
            UserIdOf = function(_self: unknown, player: Player): number
                return player.UserId
            end,
        },
    }),
    -- Default grant: a replicated attribute per benefit name; a game replaces this with its own.
    apply = function(userId: number, entry: BenefitReconciler.Entry, active: boolean)
        local player = playerById(userId)
        if player == nil then
            return
        end
        for _, benefit in entry.benefits do
            player:SetAttribute(`Benefit_{benefit}`, active)
        end
    end,
})
local function logReconcileFailures(userId: number, failures: { BenefitReconciler.Failure })
    for _, failure in failures do
        warn(`Subscription "{failure.subscription}" lookup failed for {userId}: {failure.message}`)
    end
end
if #subscriptionEntries > 0 then
    Players.UserSubscriptionStatusChanged:Connect(function(player: Player, subscriptionId: string)
        logReconcileFailures(player.UserId, reconciler:onChanged(player.UserId, subscriptionId))
    end)
    task.spawn(function()
        while true do
            task.wait(Config.default.subscriptionPollSeconds or 300)
            for _, player in Players:GetPlayers() do
                logReconcileFailures(player.UserId, reconciler:reconcile(player.UserId))
            end
        end
    end)
end

-- Rewarded video ads: opt-in, off by default; the reward is a developer product granted by
-- the receipt flow above, never by this remote.
local rewardedAdsConfig = Config.default.rewardedAds
local rewardedAds: RewardedAds.RewardedAds? = nil
if rewardedAdsConfig ~= nil then
    local adsLimiter = limiterFor("RequestRewardedAd")
    rewardedAds = RewardedAds.new({
        config = rewardedAdsConfig,
        productIdOf = function(productName: string): number?
            local product = Config.findProductByName(Config.default, productName)
            return if product ~= nil then product.id else nil
        end,
        gateway = RobloxAdService.new({
            adService = {
                CreateAdRewardFromDevProductId = function(_self: unknown, productId: number)
                    return AdService:CreateAdRewardFromDevProductId(productId)
                end,
                ShowRewardedVideoAdAsync = function(
                    _self: unknown,
                    player: Player,
                    reward,
                    placementId: number?
                ): string
                    return AdService:ShowRewardedVideoAdAsync(player, reward, placementId).Name
                end,
            },
            players = {
                GetPlayerByUserId = function(_self: unknown, userId: number): Player?
                    return playerById(userId)
                end,
            },
        }),
        allow = function(userId: number): boolean
            return adsLimiter:allow(userId)
        end,
        dayKey = function(): number
            return os.time() // 86400
        end,
    })
end
net.RequestRewardedAd.setCallback(function(player: Player, placement)
    if rewardedAds == nil then
        return
    end
    local handled = rewardedAds:handle(player.UserId, placement)
    if not handled.ok and handled.reason ~= "disabled" then
        warn(
            `RequestRewardedAd from {player.UserId} dropped: {handled.reason} {handled.detail or ""}`
        )
    end
end)

-- Private servers: owner settings and TeleportInitFailed. The platform sets the price.
local privateServersConfig = Config.default.privateServers
local privateServer: PrivateServer.PrivateServer? = nil
if privateServersConfig ~= nil then
    local settingLimiter = limiterFor("RequestPrivateServerSetting")
    local serverContext = RobloxServerContext.new({
        game = {
            PrivateServerId = game.PrivateServerId,
            PrivateServerOwnerId = game.PrivateServerOwnerId,
        },
        teleport = {
            ConnectInitFailed = function(
                _self: unknown,
                listener: (
                    player: Player,
                    resultName: string,
                    message: string,
                    targetPlaceId: number,
                    options: TeleportOptions
                ) -> ()
            ): () -> ()
                local connection = TeleportService.TeleportInitFailed:Connect(
                    function(player, result, message, targetPlaceId, options)
                        listener(player, result.Name, message, targetPlaceId, options)
                    end
                )
                return function()
                    connection:Disconnect()
                end
            end,
            TeleportAsync = function(
                _self: unknown,
                placeId: number,
                players: { Player },
                options: TeleportOptions
            )
                TeleportService:TeleportAsync(placeId, players, options)
            end,
            UserIdOf = function(_self: unknown, player: Player): number
                return player.UserId
            end,
        },
        log = function(message: string)
            warn(message)
        end,
    })
    local created = PrivateServer.new({
        config = privateServersConfig,
        context = serverContext,
        allow = function(userId: number): boolean
            return settingLimiter:allow(userId)
        end,
        delay = function(seconds: number, action: () -> ())
            task.delay(seconds, action)
        end,
        -- A game applies the setting here (for example Players.MaxPlayers is read-only at
        -- runtime, so a game decides what each setting means).
        onSettingChanged = function(setting: string, value: number)
            print(`Private server setting {setting} = {value}`)
        end,
    })
    privateServer = created
    if privateServersConfig.enabled then
        serverContext:onTeleportFailed(function(failure)
            local decision = created:handleTeleportFailed(failure)
            if decision ~= "retrying" then
                warn(`Teleport for {failure.userId} failed ({failure.result}): {decision}`)
            end
        end)
    end
end
net.RequestPrivateServerSetting.setCallback(function(player: Player, setting, value)
    if privateServer == nil then
        return
    end
    local handled = privateServer:handleSetting(player.UserId, setting, value)
    if not handled.ok and handled.reason ~= "disabled" then
        warn(`RequestPrivateServerSetting from {player.UserId} dropped: {handled.reason}`)
    end
end)

-- Roblox Plus sign-up prompt: only when the player presses the button.
local plusConfig = Config.default.plusPrompt
local plusPrompt: PlusPrompt.PlusPrompt? = nil
if plusConfig ~= nil then
    local plusLimiter = limiterFor("RequestPlusPrompt")
    local plusPort = RobloxPlusSubscription.new({
        players = {
            GetPlayerByUserId = function(_self: unknown, userId: number): Player?
                return playerById(userId)
            end,
            HasPlus = function(_self: unknown, player: Player): boolean
                return player.HasRobloxSubscription
            end,
            ConnectPlusChanged = function(
                _self: unknown,
                listener: (player: Player) -> ()
            ): () -> ()
                local connections: { RBXScriptConnection } = {}
                local function watch(player: Player)
                    table.insert(
                        connections,
                        player:GetPropertyChangedSignal("HasRobloxSubscription"):Connect(function()
                            listener(player)
                        end)
                    )
                end
                for _, player in Players:GetPlayers() do
                    watch(player)
                end
                table.insert(connections, Players.PlayerAdded:Connect(watch))
                return function()
                    for _, connection in connections do
                        connection:Disconnect()
                    end
                end
            end,
            UserIdOf = function(_self: unknown, player: Player): number
                return player.UserId
            end,
        },
        marketplace = {
            PromptRobloxSubscriptionPurchase = function(_self: unknown, player: Player)
                MarketplaceService:PromptRobloxSubscriptionPurchase(player)
            end,
        },
    })
    local createdPlus = PlusPrompt.new({
        config = plusConfig,
        port = plusPort,
        allow = function(userId: number): boolean
            return plusLimiter:allow(userId)
        end,
        clock = os.clock,
        -- Server-confirmed sign-up: a game can thank the player here. No payout code: the
        -- platform credits the sign-up bonus to the experience by itself.
        onSubscribed = function(userId: number)
            print(`Player {userId} signed up for Roblox Plus through this game`)
        end,
    })
    plusPrompt = createdPlus
    plusPort:onPlusChanged(function(userId: number, hasPlus: boolean)
        createdPlus:onPlusChanged(userId, hasPlus)
    end)
end
net.RequestPlusPrompt.setCallback(function(player: Player, placement)
    if plusPrompt == nil then
        return
    end
    local handled = plusPrompt:handle(player.UserId, placement)
    if not handled.ok and handled.reason ~= "disabled" then
        warn(`RequestPlusPrompt from {player.UserId} dropped: {handled.reason}`)
    end
end)

-- In-game Robux transfers: off by default; the platform runs the prompt and its age checks.
local transfersConfig = Config.default.robuxTransfers
local robuxTransfers: RobuxTransfers.RobuxTransfers? = nil
if transfersConfig ~= nil then
    local transferLimiter = limiterFor("RequestRobuxTransfer")
    local transferGateway = RobloxRobuxTransfers.new({
        marketplace = {
            PromptRobuxTransferAsync = function(
                _self: unknown,
                sender: Player,
                receiverUserId: number,
                amount: number
            ): string
                return MarketplaceService:PromptRobuxTransferAsync(sender, receiverUserId, amount)
            end,
            BindTransferReceipt = function(
                _self: unknown,
                receiptTypeName: string,
                handler: (
                    info: RobloxRobuxTransfers.ReceiptInfoLike
                ) -> boolean
            ): () -> ()
                local receiptType = Enum.ReceiptType:FromName(receiptTypeName)
                if receiptType == nil then
                    error(`Unknown receipt type {receiptTypeName}`)
                end
                local connection = MarketplaceService:BindReceiptHandler(
                    receiptType,
                    function(info: RobloxRobuxTransfers.ReceiptInfoLike)
                        return if handler(info)
                            then Enum.ReceiptDecision.Processed
                            else Enum.ReceiptDecision.NotProcessedYet
                    end
                )
                return function()
                    connection:Disconnect()
                end
            end,
        },
        players = {
            GetPlayerByUserId = function(_self: unknown, userId: number): Player?
                return playerById(userId)
            end,
        },
    })
    local createdTransfers = RobuxTransfers.new({
        config = transfersConfig,
        gateway = transferGateway,
        allow = function(userId: number): boolean
            return transferLimiter:allow(userId)
        end,
        isPlayerPresent = function(userId: number): boolean
            return playerById(userId) ~= nil
        end,
        onReceipt = function(receipt)
            print(`Robux transfer {receipt.side} receipt {receipt.transferRequestId}`)
        end,
    })
    robuxTransfers = createdTransfers
    if transfersConfig.enabled then
        transferGateway:bindReceipts(function(receipt)
            return createdTransfers:decideReceipt(receipt)
        end)
    end
end
net.RequestRobuxTransfer.setCallback(function(player: Player, receiverUserId, amount)
    if robuxTransfers == nil then
        return
    end
    local handled = robuxTransfers:handle(player.UserId, receiverUserId, amount)
    if not handled.ok and handled.reason ~= "disabled" then
        warn(
            `RequestRobuxTransfer from {player.UserId} dropped: {handled.reason} {handled.detail or ""}`
        )
    end
end)

-- Engagement modules (ADR 0025): promo codes, time rewards, notifications, sound.
-- Rewards use the existing ProductGrants path; every remote is rate-limited from PerfBudget.
local engagementPlayers = {
    GetPlayerByUserId = function(_self: unknown, userId: number): Player?
        return Players:GetPlayerByUserId(userId)
    end,
}
local function engagementLimiterFor(remote: string): RateLimiter.RateLimiter
    local limit = PerfBudget.clientRemotes[remote]
    return RateLimiter.new({
        capacity = limit.capacity,
        refillPerSecond = limit.refillPerSecond,
        clock = os.clock,
    })
end
local engagementLimiters: { [string]: RateLimiter.RateLimiter } = {
    RedeemCode = engagementLimiterFor("RedeemCode"),
    ClaimDailyReward = engagementLimiterFor("ClaimDailyReward"),
    ClaimSessionGift = engagementLimiterFor("ClaimSessionGift"),
    SetVolume = engagementLimiterFor("SetVolume"),
    RequestCommunityCheck = engagementLimiterFor("RequestCommunityCheck"),
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

-- Community join reward (issue #36). Off by default; membership is checked here, never trusted
-- from the client, and the grant is kept only after the profile is confirmed saved.
local communityConfig = Config.default.communityReward
local communityRequests: CommunityRewardRequests.CommunityRewardRequests? = nil
local communityReward: CommunityReward.CommunityReward? = nil
if communityConfig ~= nil and communityConfig.enabled then
    local reward = CommunityReward.new({
        config = communityConfig,
        checker = RobloxGroupMembership.new({
            players = engagementPlayers,
            isInGroup = function(player: Player, communityId: number): boolean
                return player:IsInGroupAsync(communityId)
            end,
        }),
        now = os.clock,
        profileFor = function(userId: number): PlayerData.PlayerData?
            return playerData:get(tostring(userId))
        end,
        grants = ProductGrants.new(CommunityReward.grantTable(communityConfig)),
        confirmSaved = function(userId: number): boolean
            local confirmed = playerData:confirmSaved(
                tostring(userId),
                function(saved: PlayerData.PlayerData): boolean
                    return saved.communityRewardClaimed
                end,
                Config.default.saveConfirmTimeoutSeconds
            )
            return confirmed.ok
        end,
    })
    communityReward = reward
    communityRequests = CommunityRewardRequests.new({
        reward = reward,
        notifier = notifier,
        allow = function(userId: number): boolean
            return engagementLimiters.RequestCommunityCheck:allow(userId)
        end,
    })
end
net.RequestCommunityCheck.setCallback(function(player: Player)
    local requests = communityRequests
    if requests == nil then
        return
    end
    local handled = requests:handle(player.UserId)
    if not handled.ok and handled.reason ~= "rate_limited" then
        warn(`RequestCommunityCheck from {player.UserId} not granted: {handled.reason}`)
    end
end)

local function ensureFolder(parent: Instance, name: string): Folder
    local existing = parent:FindFirstChild(name)
    if existing ~= nil and existing:IsA("Folder") then
        return existing
    end
    local created = Instance.new("Folder")
    created.Name = name
    created.Parent = parent
    return created
end
local function ensureInt(parent: Instance, name: string): IntValue
    local existing = parent:FindFirstChild(name)
    if existing ~= nil and existing:IsA("IntValue") then
        return existing
    end
    local created = Instance.new("IntValue")
    created.Name = name
    created.Parent = parent
    return created
end
local function ensureString(parent: Instance, name: string): StringValue
    local existing = parent:FindFirstChild(name)
    if existing ~= nil and existing:IsA("StringValue") then
        return existing
    end
    local created = Instance.new("StringValue")
    created.Name = name
    created.Parent = parent
    return created
end

-- Leaderboards (issue #25): leaderstats and global boards. Server to client only, through
-- replicated instances; scores are written on a schedule and never read per join.
local leaderboardsConfig = Config.default.leaderboards
local leaderboards: LeaderboardsPort.Leaderboards? = nil
if leaderboardsConfig ~= nil then
    local boardsFolder = Instance.new("Folder")
    boardsFolder.Name = "Boards"
    boardsFolder.Parent = ReplicatedStorage
    local dataStores = game:GetService("DataStoreService")
    local board = Leaderboards.new({
        config = leaderboardsConfig,
        store = OrderedDataStoreBoards.new({
            openStore = function(name: string): OrderedDataStoreBoards.StoreHandle
                local ordered = dataStores:GetOrderedDataStore(name)
                return {
                    write = function(key: string, value: number)
                        ordered:SetAsync(key, value)
                    end,
                    read = function(size: number): { { key: string, value: number } }
                        local page = ordered:GetSortedAsync(false, size):GetCurrentPage()
                        local rows: { { key: string, value: number } } = {}
                        for _, item in page do
                            local value: unknown = item.value
                            if type(value) == "number" then
                                table.insert(rows, { key = item.key, value = value })
                            end
                        end
                        return rows
                    end,
                }
            end,
        }),
        view = RobloxLeaderstats.new({
            players = engagementPlayers,
            setValue = function(player: Player, stat: string, value: number)
                local folder = ensureFolder(player, "leaderstats")
                ensureInt(folder, stat).Value = value
            end,
        }),
        publisher = ReplicatedBoardPublisher.new({
            write = function(boardId: string, text: string)
                ensureString(boardsFolder, boardId).Value = text
            end,
            encode = BoardKey.encode,
        }),
        now = os.time,
        profileFor = function(userId: number)
            return playerData:get(tostring(userId))
        end,
        onError = function(message: string)
            warn(`leaderboards: {message}`)
        end,
    })
    leaderboards = board
    task.spawn(function()
        while true do
            board:tick()
            task.wait(1)
        end
    end)
end

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
    -- The join yields: if the player left meanwhile, PlayerRemoving found no session to close and
    -- nobody else would release this one.
    if player.Parent == nil then
        playerData:leave(tostring(player.UserId))
        return
    end
    tracker:track("session_start", player.UserId, joined.value.sessionIndex)
    timeRewards:startSession(player.UserId)
    soundSettings:sendCurrent(player.UserId)
    if leaderboards ~= nil then
        leaderboards:track(player.UserId)
    end
    local requests = communityRequests
    if requests ~= nil then
        task.spawn(function()
            local checked = requests:onJoin(player.UserId)
            if not checked.ok then
                warn(`Community check on join for {player.UserId} not granted: {checked.reason}`)
            end
        end)
    end
    -- Benefits come from the live status, never from the saved profile.
    logReconcileFailures(player.UserId, reconciler:reconcile(player.UserId))
end)

Players.PlayerRemoving:Connect(function(player: Player)
    -- Final score flush first: it reads the profile that `leave` releases.
    if leaderboards ~= nil then
        leaderboards:forget(player.UserId)
    end
    if communityReward ~= nil then
        communityReward:forget(player.UserId)
    end
    playerData:leave(tostring(player.UserId))
    purchaseLimiter:forget(player.UserId)
    codes:forget(player.UserId)
    timeRewards:forget(player.UserId)
    for _, limiter in engagementLimiters do
        limiter:forget(player.UserId)
    end
    for _, limiter in remoteLimiters do
        limiter:forget(player.UserId)
    end
    reconciler:forget(player.UserId)
    if rewardedAds ~= nil then
        rewardedAds:forget(player.UserId)
    end
    if plusPrompt ~= nil then
        plusPrompt:forget(player.UserId)
    end
end)

PerfProbe.start(Config.default.perfProbeEnabled == true)

if flags:getBoolean("purchasesEnabled") then
    monetization.start()
end
