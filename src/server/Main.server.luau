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
local ChargeMeter = require(Shared.features.keysprint.ChargeMeter)
local Config = require(Shared.Config)
local Flags = require(Shared.features.flags.Flags)
local Funnel = require(Shared.features.keysprint.Funnel)
local KeySprintController = require(Shared.features.keysprint.KeySprintController)
local KeySprintRules = require(Shared.features.keysprint.KeySprintRules)
local LedgerProvider = require(Shared.ports.LedgerProvider)
local Monetization = require(Shared.features.monetization.Monetization)
local PlayerData = require(Shared.features.playerdata.PlayerData)
local ProductGrants = require(Shared.features.monetization.ProductGrants)
local PlayerDataMigrations = require(Shared.features.playerdata.PlayerDataMigrations)
local PlayerDataService = require(Shared.features.playerdata.PlayerDataService)
local PurchaseRequests = require(Shared.features.monetization.PurchaseRequests)
local PerfBudget = require(Shared.perf.PerfBudget)
local RateLimiter = require(Shared.net.RateLimiter)
local StageRuns = require(Shared.features.keysprint.StageRuns)
local net = require(Shared.net.generated.server)

local ProfileStore = require(ServerScriptService.Vendor.ProfileStore)

local AnalyticsServiceSink = require(script.Parent.adapters.AnalyticsServiceSink)
local CharacterEffects = require(script.Parent.adapters.CharacterEffects)
local ConfigServiceFlags = require(script.Parent.adapters.ConfigServiceFlags)
local MonetizationService = require(script.Parent.features.monetization.MonetizationService)
local PerfProbe = require(script.Parent.dev.PerfProbe)
local ProfileStoreRepository = require(script.Parent.adapters.ProfileStoreRepository)
local StageBuilder = require(script.Parent.adapters.StageBuilder)

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

-- Key sprint (ADR 0020). Pure rules live in shared/features/keysprint; this block only wires
-- them to engine effects. The client sends intent; every number that matters is decided here.
local stageBuilder = StageBuilder.new()
stageBuilder:build()
local characterEffects = CharacterEffects.new()

local function newRemoteLimiter(remote: string): RateLimiter.RateLimiter
    local limit = PerfBudget.clientRemotes[remote]
    return RateLimiter.new({
        capacity = limit.capacity,
        refillPerSecond = limit.refillPerSecond,
        clock = os.clock,
    })
end
local remoteLimiters: { [string]: RateLimiter.RateLimiter } = {
    PressBatch = newRemoteLimiter("PressBatch"),
    Finish = newRemoteLimiter("Finish"),
    BuyCap = newRemoteLimiter("BuyCap"),
    SkipStage = newRemoteLimiter("SkipStage"),
}
local pressLimiter = RateLimiter.new({
    capacity = KeySprintRules.PRESS_BURST,
    refillPerSecond = KeySprintRules.MAX_PRESSES_PER_SECOND,
    clock = os.clock,
})
local trailOwners: { [number]: boolean } = {}

local function playerFor(userId: number): Player?
    return Players:GetPlayerByUserId(userId)
end

local keySprint = KeySprintController.new({
    charge = ChargeMeter.new({ clock = os.clock, pressLimiter = pressLimiter }),
    runs = StageRuns.new({
        clock = os.clock,
        pathLength = function(stage: number): number
            return stageBuilder:pathLength(stage)
        end,
    }),
    funnel = Funnel.new({
        track = function(name: string, userId: number, sessionIndex: number): boolean
            return tracker:track(name, userId, sessionIndex)
        end,
    }),
    dataFor = function(userId: number): KeySprintController.Data?
        return playerData:get(tostring(userId))
    end,
    allow = function(remote: string, userId: number): boolean
        local limiter = remoteLimiters[remote]
        return limiter ~= nil and limiter:allow(userId)
    end,
    effects = {
        setWalkSpeed = function(userId: number, speed: number)
            characterEffects:setWalkSpeed(userId, speed)
        end,
        sendMultiplier = function(userId: number, multiplier: number, cap: number)
            local player = playerFor(userId)
            if player ~= nil then
                net.MultiplierChanged.fire(player, multiplier, cap)
            end
        end,
        sendProgress = function(userId: number, highestStage: number, cap: number)
            local player = playerFor(userId)
            if player ~= nil then
                net.ProgressChanged.fire(player, highestStage, cap)
            end
        end,
        sendCoins = function(userId: number, coins: number)
            local player = playerFor(userId)
            if player ~= nil then
                net.CoinsChanged.fire(player, math.min(coins, MAX_WIRE_COINS))
            end
        end,
        teleportToStage = function(userId: number, stage: number)
            characterEffects:teleportTo(userId, stageBuilder:spawnPosition(stage))
        end,
        promptSkip = function(userId: number): boolean
            local player = playerFor(userId)
            local product = Config.findProductByName(Config.default, "SkipStage")
            if player == nil or product == nil or product.id == nil then
                return false
            end
            MarketplaceService:PromptProductPurchase(player, product.id)
            return true
        end,
    },
})

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
        if product.grant.kind == "skipStage" then
            keySprint:onProgressGranted(receipt.playerId)
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
-- RequestPurchase carries coin packs only; Skip stage has its own remote (SkipStage).
local purchaseNames: { string } = {}
for _, product in Config.default.developerProducts do
    if product.grant.kind == "coins" then
        table.insert(purchaseNames, product.name)
    end
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

-- Key sprint remotes: the generated layer decodes, the controller rate-limits, validates, acts.
local function report(remote: string, userId: number, outcome: KeySprintController.Outcome)
    if not outcome.ok and outcome.reason ~= "rate_limited" then
        warn(`{remote} from {userId} dropped: {outcome.reason}`)
    end
end
net.PressBatch.setCallback(function(player: Player, presses)
    report("PressBatch", player.UserId, keySprint:onPressBatch(player.UserId, presses))
end)
net.Finish.setCallback(function(player: Player, stage)
    report("Finish", player.UserId, keySprint:onFinish(player.UserId, stage))
end)
net.BuyCap.setCallback(function(player: Player)
    report("BuyCap", player.UserId, keySprint:onBuyCap(player.UserId))
end)
net.SkipStage.setCallback(function(player: Player)
    report("SkipStage", player.UserId, keySprint:onSkipStageRequest(player.UserId))
end)

-- Passes: ownership is read from Roblox at join and when a purchase finishes, never from the client.
local function applyPass(userId: number, passName: string, owns: boolean)
    if passName == "FasterCharge" then
        keySprint:setFasterCharge(userId, owns)
    elseif passName == "Trail" then
        trailOwners[userId] = owns
        if owns then
            characterEffects:applyTrail(userId)
        end
    end
end

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
            applyPass(player.UserId, pass.name, owns)
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
                applyPass(player.UserId, pass.name, true)
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
    -- session_start and the tutorial events come from the Key sprint funnel (Funnel).
    keySprint:onJoin(player.UserId, joined.value.sessionIndex)
    refreshPasses(player)
    -- The checkpoint: every spawn puts the character at the start gate of the stage in progress.
    player.CharacterAdded:Connect(function()
        keySprint:onRespawn(player.UserId)
        if trailOwners[player.UserId] then
            characterEffects:applyTrail(player.UserId)
        end
    end)
    if player.Character ~= nil then
        keySprint:onRespawn(player.UserId)
    end
end)

Players.PlayerRemoving:Connect(function(player: Player)
    keySprint:onLeave(player.UserId)
    playerData:leave(tostring(player.UserId))
    purchaseLimiter:forget(player.UserId)
    pressLimiter:forget(player.UserId)
    for _, limiter in remoteLimiters do
        limiter:forget(player.UserId)
    end
    trailOwners[player.UserId] = nil
end)

-- Reports multiplier decay to the client and keeps the server walk speed in step.
task.spawn(function()
    while true do
        task.wait(0.25)
        local userIds: { number } = {}
        for _, player in Players:GetPlayers() do
            table.insert(userIds, player.UserId)
        end
        keySprint:tick(userIds)
    end
end)

PerfProbe.start(Config.default.perfProbeEnabled == true)

if flags:getBoolean("purchasesEnabled") then
    monetization.start()
end
