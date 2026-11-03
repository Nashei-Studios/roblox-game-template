--!strict
--[[
    The ONLY server Script: the composition root (ADR 0009). It builds adapters over engine
    services and ProfileStore, injects them into the feature services, and connects engine
    events. Game-specific wiring goes here; logic goes in features.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local ConfigService = game:GetService("ConfigService")
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

local ProfileStore = require(ServerScriptService.Vendor.ProfileStore)

local AnalyticsServiceSink = require(script.Parent.adapters.AnalyticsServiceSink)
local ConfigServiceFlags = require(script.Parent.adapters.ConfigServiceFlags)
local MonetizationService = require(script.Parent.features.monetization.MonetizationService)
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
local repository = ProfileStoreRepository.new(store)
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

local productGrants = ProductGrants.new(Config.grantsByName(Config.default))

local monetization = MonetizationService.new({
    ledgers = ledgers,
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
        return true
    end,
})

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
end)

Players.PlayerRemoving:Connect(function(player: Player)
    playerData:leave(tostring(player.UserId))
end)

if flags:getBoolean("purchasesEnabled") then
    monetization.start()
end
